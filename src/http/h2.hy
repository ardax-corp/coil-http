// HTTP/2 framing (RFC 7540 §4), cleartext prior-knowledge (§3.4), and TLS ALPN `h2`.
// HPACK static table is in http::hpack. In-memory mux lives in http::h2_session.
// `h2_serve` is still a stub. HTTPS `h2_connect` enables TLS with `h2,http/1.1` and
// falls back to HTTP/1.1 when ALPN is not `h2`.
use conv::{int_to_dec};
use http::hpack::{decode_header_block, encode_header_block};
use http::url::{
    HttpError,
    Headers,
    Url,
    empty_headers,
    http_err_bad_response,
    http_err_io,
    http_err_not_supported,
    http_fail_stream,
    http_fail_unit,
    parse_url,
};
use http::request::{build_request_head};
use http::response::{Response, bytes_slice_resp, parse_response};
use http::conn::{HttpConn, close_conn, read_http_message};
use io::{Stream, close as io_close, read, to_bytes, IoError, await_readable};
use io::net::tcp::connect as tcp_connect;
use io::net::tls::{alpn_protocol};
use io::net::tls::client::enable as tls_enable;
use io::sync::{write_all};

class H2Frame {
    typ: int,
    flags: int,
    stream_id: int,
    payload: Vec<byte>,
}

impl H2Frame {
    static fn new(int typ, int flags, int stream_id, Vec<byte> payload) -> H2Frame {
        return new H2Frame(typ, flags, stream_id, payload);
    }
}

/// SETTINGS identifier/value pairs (RFC 7540 §6.5).
class H2Settings {
    ids: Vec<int>,
    values: Vec<int>,
}

impl H2Settings {
    static fn new() -> H2Settings {
        let ids: Vec<int> = Vec::new();
        let values: Vec<int> = Vec::new();
        return new H2Settings(ids, values);
    }

    fn add(int id, int value) {
        self.ids.push(id);
        self.values.push(value);
    }

    fn count() -> int {
        return len(self.ids);
    }
}

/// GOAWAY last-stream-id and error code (RFC 7540 §6.8). Debug data after 8 bytes is ignored on decode.
class H2Goaway {
    last_stream_id: int,
    error_code: int,
}

impl H2Goaway {
    static fn new(int last_stream_id, int error_code) -> H2Goaway {
        return new H2Goaway(last_stream_id, error_code);
    }
}

fn frame_type_data() -> int {
    return 0;
}

fn frame_type_headers() -> int {
    return 1;
}

fn frame_type_settings() -> int {
    return 4;
}

fn frame_type_ping() -> int {
    return 6;
}

fn frame_type_goaway() -> int {
    return 7;
}

fn frame_type_window_update() -> int {
    return 8;
}

fn flag_ack() -> int {
    return 1;
}

fn flag_end_stream() -> int {
    return 1;
}

fn flag_end_headers() -> int {
    return 4;
}

fn two31() -> int {
    return 128 * 16777216;
}

fn push_u8(Vec<byte> out, int n) {
    let mod256 = 128 + 128;
    let b: byte = ((n % mod256) as byte);
    out.push(b);
}

fn encode_frame(H2Frame f) -> Vec<byte> {
    let n = len(f.payload);
    let out: Vec<byte> = Vec::new();
    push_u8(out, n / 65536);
    push_u8(out, n / 256);
    push_u8(out, n);
    push_u8(out, f.typ);
    push_u8(out, f.flags);
    let sid = f.stream_id;
    push_u8(out, sid / 16777216);
    push_u8(out, sid / 65536);
    push_u8(out, sid / 256);
    push_u8(out, sid);
    let i = 0;
    while i < n {
        out.push(f.payload[i]);
        i = i + 1;
    }
    return out;
}

fn u8_at(Vec<byte> raw, int i) -> int {
    return (raw[i] as int);
}

/// Complete first-frame size (9 + length), or 0 if `raw` is truncated.
fn frame_wire_len(Vec<byte> raw) -> int {
    if len(raw) < 9 {
        return 0;
    }
    let n = u8_at(raw, 0) * 65536 + u8_at(raw, 1) * 256 + u8_at(raw, 2);
    if len(raw) < 9 + n {
        return 0;
    }
    return 9 + n;
}

/// Parse the first HTTP/2 frame in `raw`. Extra bytes after the frame are ignored.
fn decode_frame(Vec<byte> raw) -> Result<H2Frame, HttpError> {
    if len(raw) < 9 {
        http_err_bad_response()?;
    }
    let n = u8_at(raw, 0) * 65536 + u8_at(raw, 1) * 256 + u8_at(raw, 2);
    if len(raw) < 9 + n {
        http_err_bad_response()?;
    }
    let typ = u8_at(raw, 3);
    let flags = u8_at(raw, 4);
    let sid = u8_at(raw, 5) * 16777216 + u8_at(raw, 6) * 65536 + u8_at(raw, 7) * 256 + u8_at(raw, 8);
    sid = sid % two31();
    let payload = bytes_slice_resp(raw, 9, 9 + n);
    return H2Frame::new(typ, flags, sid, payload);
}

fn connection_preface() -> Vec<byte> {
    return to_bytes("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n");
}

fn preface_ok(Vec<byte> raw) -> int {
    let want = connection_preface();
    if len(raw) < len(want) {
        return 0;
    }
    let i = 0;
    while i < len(want) {
        if raw[i] != want[i] {
            return 0;
        }
        i = i + 1;
    }
    return 1;
}

fn empty_settings_frame() -> H2Frame {
    let payload: Vec<byte> = Vec::new();
    return H2Frame::new(frame_type_settings(), 0, 0, payload);
}

fn push_u16(Vec<byte> out, int n) {
    push_u8(out, n / 256);
    push_u8(out, n);
}

fn push_u32(Vec<byte> out, int n) {
    push_u8(out, n / 16777216);
    push_u8(out, n / 65536);
    push_u8(out, n / 256);
    push_u8(out, n);
}

fn u16_at(Vec<byte> raw, int i) -> int {
    return u8_at(raw, i) * 256 + u8_at(raw, i + 1);
}

fn u32_at(Vec<byte> raw, int i) -> int {
    return u8_at(raw, i) * 16777216 + u8_at(raw, i + 1) * 65536 + u8_at(raw, i + 2) * 256 + u8_at(raw, i + 3);
}

/// Encode SETTINGS parameters. Each pair is 2-byte identifier + 4-byte value.
fn encode_settings_payload(H2Settings s) -> Vec<byte> {
    let out: Vec<byte> = Vec::new();
    let i = 0;
    let n = s.count();
    while i < n {
        push_u16(out, s.ids[i]);
        push_u32(out, s.values[i]);
        i = i + 1;
    }
    return out;
}

/// Decode SETTINGS payload. Length must be a multiple of 6 (ACK uses empty payload).
fn decode_settings_payload(Vec<byte> raw) -> Result<H2Settings, HttpError> {
    let n = len(raw);
    if n % 6 != 0 {
        http_err_bad_response()?;
    }
    let s = H2Settings::new();
    let i = 0;
    while i < n {
        s.add(u16_at(raw, i), u32_at(raw, i + 2));
        i = i + 6;
    }
    return s;
}

fn settings_frame(H2Settings s) -> H2Frame {
    return H2Frame::new(frame_type_settings(), 0, 0, encode_settings_payload(s));
}

fn settings_ack_frame() -> H2Frame {
    let payload: Vec<byte> = Vec::new();
    return H2Frame::new(frame_type_settings(), flag_ack(), 0, payload);
}

/// Encode WINDOW_UPDATE increment (31-bit). Increment 0 is PROTOCOL_ERROR / BadResponse.
fn encode_window_update_payload(int increment) -> Result<Vec<byte>, HttpError> {
    if increment == 0 {
        http_err_bad_response()?;
    }
    let inc = increment % two31();
    if inc == 0 {
        http_err_bad_response()?;
    }
    let out: Vec<byte> = Vec::new();
    push_u32(out, inc);
    return out;
}

/// Decode 4-byte WINDOW_UPDATE. Reserved bit is cleared; increment 0 is an error.
fn decode_window_update_payload(Vec<byte> raw) -> Result<int, HttpError> {
    if len(raw) != 4 {
        http_err_bad_response()?;
    }
    let inc = u32_at(raw, 0) % two31();
    if inc == 0 {
        http_err_bad_response()?;
    }
    return inc;
}

fn window_update_frame(int stream_id, int increment) -> Result<H2Frame, HttpError> {
    let payload = encode_window_update_payload(increment)?;
    return H2Frame::new(frame_type_window_update(), 0, stream_id, payload);
}

/// Encode GOAWAY: 31-bit last-stream-id + 32-bit error code.
fn encode_goaway_payload(int last_stream_id, int error_code) -> Vec<byte> {
    let out: Vec<byte> = Vec::new();
    push_u32(out, last_stream_id % two31());
    push_u32(out, error_code);
    return out;
}

/// Decode GOAWAY. Requires at least 8 bytes; extra debug data is ignored.
fn decode_goaway_payload(Vec<byte> raw) -> Result<H2Goaway, HttpError> {
    if len(raw) < 8 {
        http_err_bad_response()?;
    }
    let last = u32_at(raw, 0) % two31();
    let code = u32_at(raw, 4);
    return H2Goaway::new(last, code);
}

fn goaway_frame(int last_stream_id, int error_code) -> H2Frame {
    return H2Frame::new(frame_type_goaway(), 0, 0, encode_goaway_payload(last_stream_id, error_code));
}

/// HEADERS frame with HPACK payload. END_HEADERS is always set; END_STREAM when `end_stream` is nonzero.
fn headers_frame(int stream_id, Headers h, int end_stream) -> H2Frame {
    let payload = encode_header_block(h);
    let flags = flag_end_headers();
    if end_stream != 0 {
        flags = flags + flag_end_stream();
    }
    return H2Frame::new(frame_type_headers(), flags, stream_id, payload);
}

fn headers_from_frame(H2Frame f) -> Result<Headers, HttpError> {
    if f.typ != frame_type_headers() {
        http_err_bad_response()?;
    }
    return decode_header_block(f.payload)?;
}

/// DATA frame. END_STREAM when `end_stream` is nonzero.
fn data_frame(int stream_id, Vec<byte> payload, int end_stream) -> H2Frame {
    let flags = 0;
    if end_stream != 0 {
        flags = flag_end_stream();
    }
    return H2Frame::new(frame_type_data(), flags, stream_id, payload);
}

fn h2_append(Vec<byte> out, Vec<byte> extra) {
    let i = 0;
    while i < len(extra) {
        out.push(extra[i]);
        i = i + 1;
    }
}

fn h2_cat(Vec<byte> a, Vec<byte> b) -> Vec<byte> {
    let out: Vec<byte> = Vec::new();
    h2_append(out, a);
    h2_append(out, b);
    return out;
}

/// `:authority` is `host` on default ports, otherwise `host:port`.
fn h2_authority(Url u) -> string {
    let host = u.host;
    let port = u.port;
    if u.scheme == "http" {
        if port == 80 {
            return host;
        }
    }
    if u.scheme == "https" {
        if port == 443 {
            return host;
        }
    }
    return host + ":" + int_to_dec(port);
}

fn h2_get_request_headers(Url u) -> Headers {
    let h = Headers::new();
    h.add(":method", "GET");
    h.add(":path", u.path);
    h.add(":scheme", u.scheme);
    h.add(":authority", h2_authority(u));
    return h;
}

/// Connection preface + empty SETTINGS + GET HEADERS (END_HEADERS|END_STREAM) on stream 1.
fn h2_prior_knowledge_get(Url u) -> Vec<byte> {
    let out = connection_preface();
    h2_append(out, encode_frame(empty_settings_frame()));
    h2_append(out, encode_frame(headers_frame(1, h2_get_request_headers(u), 1)));
    return out;
}

fn h2_parse_status_digits(string s) -> int {
    let b = to_bytes(s);
    let v = 0;
    let i = 0;
    while i < len(b) {
        v = v * 10 + ((b[i] as int) - (("0" as byte) as int));
        i = i + 1;
    }
    return v;
}

fn h2_status_from_headers(Headers h) -> int {
    let i = 0;
    let n = h.count();
    while i < n {
        if h.name_at(i) == ":status" {
            return h2_parse_status_digits(h.value_at(i));
        }
        i = i + 1;
    }
    return 200;
}

fn h2_close(Stream s) {
    match io_close(s) {
        Result::Ok(_) => 0,
        Result::Err(_) => 0,
    };
}

/// Blocking read of `n` bytes. Waits on `WouldBlock`; EOF is BadResponse.
fn h2_read_n(Stream s, int n) -> Result<Vec<byte>, HttpError> {
    if n == 0 {
        let empty: Vec<byte> = Vec::new();
        return empty;
    }
    let buf: Vec<byte> = Vec::new();
    let z: byte = 0;
    let k = 0;
    while k < n {
        buf.push(z);
        k = k + 1;
    }
    let filled = 0;
    while filled < n {
        let remaining = n - filled;
        let scratch: Vec<byte> = Vec::new();
        let i = 0;
        while i < remaining {
            scratch.push(z);
            i = i + 1;
        }
        match read(s, scratch) {
            Result::Ok(opt) => {
                match opt {
                    Option::None => {
                        http_err_bad_response()?;
                    },
                    Option::Some(got) => {
                        if got == 0 {
                            match await_readable(s) {
                                Result::Ok(_) => 0,
                                Result::Err(_) => {
                                    http_err_io()?;
                                    0
                                },
                            };
                        }
                        if got != 0 {
                            let j = 0;
                            while j < got {
                                buf[filled + j] = scratch[j];
                                j = j + 1;
                            }
                            filled = filled + got;
                        }
                    },
                };
                0
            },
            Result::Err(IoError::WouldBlock) => {
                match await_readable(s) {
                    Result::Ok(_) => 0,
                    Result::Err(_) => {
                        http_err_io()?;
                        0
                    },
                };
                0
            },
            Result::Err(_) => {
                http_err_io()?;
                0
            },
        };
    }
    return buf;
}

fn h2_write_frame(Stream s, H2Frame f) -> Result<(), HttpError> {
    match write_all(s, encode_frame(f)) {
        Result::Ok(_) => 0,
        Result::Err(_) => {
            http_fail_unit()?;
            0
        },
    };
    return ();
}

/// One complete frame: 9-byte header, then payload; `frame_wire_len` must match.
fn h2_read_frame(Stream s) -> Result<H2Frame, HttpError> {
    let hdr = h2_read_n(s, 9)?;
    let n = u8_at(hdr, 0) * 65536 + u8_at(hdr, 1) * 256 + u8_at(hdr, 2);
    let payload = h2_read_n(s, n)?;
    let raw = h2_cat(hdr, payload);
    if frame_wire_len(raw) != 9 + n {
        http_err_bad_response()?;
    }
    return decode_frame(raw)?;
}

/// HTTP/2 over a connected stream (cleartext prior-knowledge or TLS ALPN `h2`).
fn h2_get_over_h2(Stream s, Url u) -> Result<Response, HttpError> {
    match write_all(s, h2_prior_knowledge_get(u)) {
        Result::Ok(_) => 0,
        Result::Err(_) => {
            h2_close(s);
            http_fail_unit()?;
            0
        },
    };
    let status = 200;
    let got_headers = 0;
    let body: Vec<byte> = Vec::new();
    let done = 0;
    let guard = 0;
    while done == 0 {
        if guard >= 64 {
            h2_close(s);
            http_err_bad_response()?;
        }
        let f = match h2_read_frame(s) {
            Result::Ok(v) => v,
            Result::Err(e) => {
                h2_close(s);
                raise e;
            },
        };
        if f.typ == frame_type_settings() {
            if f.flags % 2 == 0 {
                match h2_write_frame(s, settings_ack_frame()) {
                    Result::Ok(_) => 0,
                    Result::Err(e) => {
                        h2_close(s);
                        raise e;
                    },
                };
            }
        }
        if f.stream_id == 1 {
            if f.typ == frame_type_headers() {
                let h = match headers_from_frame(f) {
                    Result::Ok(v) => v,
                    Result::Err(e) => {
                        h2_close(s);
                        raise e;
                    },
                };
                status = h2_status_from_headers(h);
                got_headers = 1;
                if f.flags % 2 == 1 {
                    done = 1;
                }
            }
            if f.typ == frame_type_data() {
                h2_append(body, f.payload);
                if f.flags % 2 == 1 {
                    done = 1;
                }
            }
        }
        guard = guard + 1;
    }
    h2_close(s);
    if got_headers == 0 {
        http_err_bad_response()?;
    }
    let r = Response::ok();
    r.status(status);
    r.body(body);
    return r;
}

/// HTTP/1.1 GET on an already-handshaken TLS (or TCP) stream.
fn h2_http11_get(Stream s, Url u) -> Result<Response, HttpError> {
    let headers = empty_headers();
    let head = match build_request_head("GET", u, headers, 0) {
        Result::Ok(v) => v,
        Result::Err(e) => {
            h2_close(s);
            raise e;
        },
    };
    match write_all(s, head) {
        Result::Ok(_) => 0,
        Result::Err(_) => {
            h2_close(s);
            http_fail_unit()?;
            0
        },
    };
    let c = HttpConn::wrap(s);
    let raw = match read_http_message(c) {
        Result::Ok(b) => b,
        Result::Err(e) => {
            close_conn(c);
            raise e;
        },
    };
    let resp = match parse_response(raw) {
        Result::Ok(r) => r,
        Result::Err(e) => {
            close_conn(c);
            raise e;
        },
    };
    close_conn(c);
    return resp;
}

/// Client ALPN offer list for HTTPS `h2_connect` (prefer h2, allow HTTP/1.1).
fn h2_client_alpn() -> string {
    return "h2,http/1.1";
}

/// Exact ALPN `h2` means speak HTTP/2; anything else (incl. empty) falls back to HTTP/1.1.
fn h2_alpn_is_h2(string proto) -> int {
    if proto == "h2" {
        return 1;
    }
    return 0;
}

/// `h2_serve` stays a stub (TLS server ALPN mux is later).
fn h2_not_supported() -> Result<(), HttpError> {
    http_err_not_supported()?;
    return ();
}

/// GET: cleartext prior-knowledge, or HTTPS TLS ALPN `h2` with HTTP/1.1 fallback.
fn h2_connect(string url) -> Result<Response, HttpError> {
    let u = parse_url(url)?;
    let tcp = match tcp_connect(u.host, u.port) {
        Result::Ok(v) => v,
        Result::Err(_) => http_fail_stream()?,
    };
    if u.scheme == "https" {
        let s = match tls_enable(tcp, u.host, { verify: true, ca_pem: Option::None, ca_path: Option::None, timeout_ms: 0, alpn: h2_client_alpn() }) {
            Result::Ok(v) => v,
            Result::Err(_) => {
                h2_close(tcp);
                http_fail_stream()?
            },
        };
        let proto = match alpn_protocol(s) {
            Result::Ok(p) => p,
            Result::Err(_) => {
                h2_close(s);
                http_err_io()?;
                ""
            },
        };
        if h2_alpn_is_h2(proto) == 1 {
            return h2_get_over_h2(s, u)?;
        }
        return h2_http11_get(s, u)?;
    }
    return h2_get_over_h2(tcp, u)?;
}

fn h2_serve() -> Result<(), HttpError> {
    h2_not_supported()?;
    return ();
}
