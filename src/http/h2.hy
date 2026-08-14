// HTTP/2 framing (RFC 7540 §4). HPACK static table is in http::hpack; mux is still NotSupported on the wire.
use http::hpack::{decode_header_block, encode_header_block};
use http::url::{HttpError, Headers, http_err_bad_response, http_err_not_supported};
use http::response::{bytes_slice_resp};
use io::{to_bytes};

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

/// HTTP/2 client/server sessions are not on the wire yet (HPACK + mux).
fn h2_not_supported() -> Result<(), HttpError> {
    http_err_not_supported()?;
    return ();
}

fn h2_connect(string url) -> Result<(), HttpError> {
    h2_not_supported()?;
    return ();
}

fn h2_serve() -> Result<(), HttpError> {
    h2_not_supported()?;
    return ();
}
