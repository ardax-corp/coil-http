// WebSocket (RFC 6455) over HTTP/1.1 upgrade. Framing + handshake; not a new transport.
use encoding::{encode};
use conv::{int_to_dec};
use io::{Stream, close as io_close, read, IoError, wait_readable};
use string::{to_bytes};
use io::net::tcp::connect as tcp_connect;
use io::sync::{accept_wait, write_all};
use tls::client::{enable as tls_enable, ClientOpts};
use http::sha1::{sha1};
use http::url::{
    HttpError,
    Url,
    header_name_eq_ci,
    http_err_protocol,
    http_err_bad_url,
    http_err_io,
    http_err_unsupported_scheme,
    http_fail_stream,
    http_fail_unit,
    parse_url,
    http_fail_tls,
    http_not_bound,
};
use http::h1::{IncomingRequest, parse_request};
use http::request::{concat_bytes};
use http::response::{Response, bytes_slice_resp, header_get, parse_response};
use http::conn::{HttpConn, close_conn, read_http_message};
use http::server::{Server};

/// One WebSocket frame (RFC 6455 §5.2), as `ws_recv` and `decode_ws_frame` return it.
///
/// `opcode` is one of the `ws_opcode_*` values. `payload` is already unmasked.
///
/// # Examples
///
/// ```
/// # use tests::assert;
/// use http::ws::{decode_ws_frame, encode_ws_frame, ws_opcode_text};
/// use string::to_bytes;
///
/// let no_mask: Vec<byte> = Vec::new();
/// let wire = encode_ws_frame(1, ws_opcode_text(), no_mask, to_bytes("hi"));
/// let f = match decode_ws_frame(wire) {
///     Result::Ok(f) => f,
///     Result::Err(e) => panic show(e),
/// };
/// assert!(f.fin == 1);
/// assert!(f.opcode == ws_opcode_text());
/// assert!(f.masked == 0);
/// assert!(f.payload.len() == 2);
/// ```
class WsFrame {
    /// 1 when this is the final frame of a message.
    pub fin: int,
    /// Frame type: text, binary, close, ping, pong or continuation (`ws_opcode_*`).
    pub opcode: int,
    /// 1 when the frame arrived masked (client to server).
    pub masked: int,
    /// Payload bytes, unmasked.
    pub payload: Vec<byte>,
}

impl WsFrame {
    /// A frame from its parts.
    pub static fn new(int fin, int opcode, int masked, Vec<byte> payload) -> WsFrame {
        return new WsFrame(fin, opcode, masked, payload);
    }
}

/// An open WebSocket over an upgraded HTTP/1.1 connection.
///
/// Made by `ws_connect` (client) or `ws_serve_once` / `ws_upgrade` (server).
/// Send with `ws_send_text`, `ws_send_bin`, `ws_send_ping`, `ws_send_pong` and
/// `ws_send_close`; read with `ws_recv`; end with `ws_close`. A client masks every
/// frame it sends, as RFC 6455 requires; a server never does.
///
/// v1 limits: no fragmented messages, no extensions or subprotocols, payloads up
/// to 1 MiB, and no WebSocket over HTTP/2.
///
/// # Examples
///
/// ```no_run
/// use http::ws::{ws_close, ws_connect, ws_opcode_text, ws_recv, ws_send_close, ws_send_text};
/// use http::url::HttpError;
/// use string::from_bytes;
///
/// fn main() -> Result<(), HttpError> {
///     let c = ws_connect("ws://127.0.0.1:8080/echo")?;
///     ws_send_text(c, "hello")?;
///     let f = ws_recv(c)?;
///     if f.opcode == ws_opcode_text() {
///         let text = from_bytes(f.payload);
///     }
///     ws_send_close(c)?;
///     ws_close(c);
///     return ();
/// }
/// ```
class WsConn {
    /// The upgraded HTTP/1.1 connection.
    pub conn: HttpConn,
    /// 1 for a client (masks outbound frames), 0 for a server.
    pub role: int,
    /// 1 once `ws_close` closed the connection.
    pub closed: int,
    /// State of the masking-key generator.
    pub seed: int,
}

impl WsConn {
    fn drop() {
        if self.closed == 0 {
            self.closed = 1;
            close_conn(self.conn);
        }
        self.role = self.role;
    }
}

fn ws_guid() -> string {
    return "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
}

/// Opcode 0: continuation frame.
fn ws_opcode_cont() -> int {
    return 0;
}

/// Opcode 1: text frame (UTF-8 payload).
fn ws_opcode_text() -> int {
    return 1;
}

/// Opcode 2: binary frame.
fn ws_opcode_bin() -> int {
    return 2;
}

/// Opcode 8: close frame.
fn ws_opcode_close() -> int {
    return 8;
}

/// Opcode 9: ping frame.
fn ws_opcode_ping() -> int {
    return 9;
}

/// Opcode 10: pong frame.
fn ws_opcode_pong() -> int {
    return 10;
}

fn ws_mod256() -> int {
    return 128 + 128;
}

fn ws_b16() -> int {
    let m = ws_mod256();
    return m * m;
}

fn ws_b24() -> int {
    return ws_b16() * ws_mod256();
}

fn ws_u8(int n) -> byte {
    let m = ws_mod256();
    return (n % m) as byte;
}

fn ws_push_u8(Vec<byte> out, int n) {
    out.push(ws_u8(n));
}

fn ws_push_u16be(Vec<byte> out, int n) {
    ws_push_u8(out, n / ws_mod256());
    ws_push_u8(out, n);
}

fn ws_push_u64be(Vec<byte> out, int n) {
    ws_push_u8(out, 0);
    ws_push_u8(out, 0);
    ws_push_u8(out, 0);
    ws_push_u8(out, 0);
    ws_push_u8(out, n / ws_b24());
    ws_push_u8(out, n / ws_b16());
    ws_push_u8(out, n / ws_mod256());
    ws_push_u8(out, n);
}

fn ws_mask_apply(Vec<byte> payload, Vec<byte> key) -> Vec<byte> {
    let out: Vec<byte> = Vec::new();
    let i = 0;
    while i < payload.len() {
        let x = (payload[i] as int) ^ (key[i % 4] as int);
        out.push(ws_u8(x));
        i = i + 1;
    }
    return out;
}

fn ws_max_payload() -> int {
    return 1048576;
}

/// Encodes one frame.
///
/// `fin` 1 marks the final frame. A 4-byte `mask_key` masks the payload (client
/// to server); an empty one sends it unmasked. The length uses the 7-, 16- or
/// 64-bit form as needed.
fn encode_ws_frame(int fin, int opcode, Vec<byte> mask_key, Vec<byte> payload) -> Vec<byte> {
    let out: Vec<byte> = Vec::new();
    let b0 = opcode & 15;
    if fin == 1 {
        b0 = b0 | 128;
    }
    ws_push_u8(out, b0);
    let n = payload.len();
    let masked = 0;
    if mask_key.len() == 4 {
        masked = 128;
    }
    if n < 126 {
        ws_push_u8(out, masked + n);
    } else {
        if n < ws_b16() {
            ws_push_u8(out, masked + 126);
            ws_push_u16be(out, n);
        } else {
            ws_push_u8(out, masked + 127);
            ws_push_u64be(out, n);
        }
    }
    let data = payload;
    if masked == 128 {
        let i = 0;
        while i < 4 {
            out.push(mask_key[i]);
            i = i + 1;
        }
        data = ws_mask_apply(payload, mask_key);
    }
    let j = 0;
    while j < data.len() {
        out.push(data[j]);
        j = j + 1;
    }
    return out;
}

fn ws_u8_at(Vec<byte> raw, int i) -> int {
    return raw[i] as int;
}

/// Decodes the first complete frame in `raw`, unmasking the payload. Bytes after
/// it are ignored.
///
/// Returns `Protocol` when `raw` is truncated, a reserved (RSV) bit is set, or the
/// payload is over 1 MiB.
fn decode_ws_frame(Vec<byte> raw) -> Result<WsFrame, HttpError> {
    if raw.len() < 2 {
        http_err_protocol()?;
    }
    let b0 = ws_u8_at(raw, 0);
    let b1 = ws_u8_at(raw, 1);
    let rsv = (b0 >> 4) & 7;
    if rsv != 0 {
        http_err_protocol()?;
    }
    let fin = (b0 >> 7) & 1;
    let opcode = b0 & 15;
    let masked = (b1 >> 7) & 1;
    let llen = b1 & 127;
    let pos = 2;
    let n = llen;
    if llen == 126 {
        if raw.len() < 4 {
            http_err_protocol()?;
        }
        n = ws_u8_at(raw, 2) * ws_mod256() + ws_u8_at(raw, 3);
        pos = 4;
    }
    if llen == 127 {
        if raw.len() < 10 {
            http_err_protocol()?;
        }
        if ws_u8_at(raw, 2) != 0 {
            http_err_protocol()?;
        }
        if ws_u8_at(raw, 3) != 0 {
            http_err_protocol()?;
        }
        if ws_u8_at(raw, 4) != 0 {
            http_err_protocol()?;
        }
        if ws_u8_at(raw, 5) != 0 {
            http_err_protocol()?;
        }
        n = ws_u8_at(raw, 6) * ws_b24() + ws_u8_at(raw, 7) * ws_b16() + ws_u8_at(raw, 8) * ws_mod256() + ws_u8_at(raw, 9);
        pos = 10;
    }
    if n > ws_max_payload() {
        http_err_protocol()?;
    }
    let key: Vec<byte> = Vec::new();
    if masked == 1 {
        if raw.len() < pos + 4 {
            http_err_protocol()?;
        }
        key.push(raw[pos]);
        key.push(raw[pos + 1]);
        key.push(raw[pos + 2]);
        key.push(raw[pos + 3]);
        pos = pos + 4;
    }
    if raw.len() < pos + n {
        http_err_protocol()?;
    }
    let payload = bytes_slice_resp(raw, pos, pos + n);
    if masked == 1 {
        payload = ws_mask_apply(payload, key);
    }
    return WsFrame::new(fin, opcode, masked, payload);
}

/// The byte length of the first complete frame in `raw`, or 0 when `raw` is truncated.
fn ws_frame_wire_len(Vec<byte> raw) -> int {
    if raw.len() < 2 {
        return 0;
    }
    let b1 = ws_u8_at(raw, 1);
    let masked = (b1 >> 7) & 1;
    let llen = b1 & 127;
    let extra = 0;
    let n = llen;
    if llen == 126 {
        if raw.len() < 4 {
            return 0;
        }
        extra = 2;
        n = ws_u8_at(raw, 2) * ws_mod256() + ws_u8_at(raw, 3);
    }
    if llen == 127 {
        if raw.len() < 10 {
            return 0;
        }
        extra = 8;
        n = ws_u8_at(raw, 6) * ws_b24() + ws_u8_at(raw, 7) * ws_b16() + ws_u8_at(raw, 8) * ws_mod256() + ws_u8_at(raw, 9);
    }
    let maskn = 0;
    if masked == 1 {
        maskn = 4;
    }
    let total = 2 + extra + maskn + n;
    if raw.len() < total {
        return 0;
    }
    return total;
}

fn ws_ascii_lower(int x) -> int {
    if x >= 65 {
        if x <= 90 {
            return x + 32;
        }
    }
    return x;
}

fn ws_contains_ci(string hay, string needle) -> int {
    let hb = to_bytes(hay);
    let nb = to_bytes(needle);
    if nb.len() == 0 {
        return 1;
    }
    if nb.len() > hb.len() {
        return 0;
    }
    let i = 0;
    while i + nb.len() <= hb.len() {
        let ok = 1;
        let j = 0;
        while j < nb.len() {
            if ws_ascii_lower(hb[i + j] as int) != ws_ascii_lower(nb[j] as int) {
                ok = 0;
            }
            j = j + 1;
        }
        if ok == 1 {
            return 1;
        }
        i = i + 1;
    }
    return 0;
}

fn ws_header_get_req(IncomingRequest req, string name) -> string {
    let h = req.headers_val();
    let i = 0;
    while i < h.names.len() {
        if header_name_eq_ci(h.names[i], name) == 1 {
            return h.values[i];
        }
        i = i + 1;
    }
    return "";
}

fn ws_header_get_resp(Response r, string name) -> string {
    let i = 0;
    while i < r.header_names.len() {
        if header_name_eq_ci(r.header_names[i], name) == 1 {
            return r.header_values[i];
        }
        i = i + 1;
    }
    let v = header_get(r, name);
    return v;
}

/// The `Sec-WebSocket-Accept` value for a client's `Sec-WebSocket-Key`:
/// Base64(SHA-1(key + RFC 6455 GUID)).
///
/// # Examples
///
/// ```
/// # use tests::assert;
/// use http::ws::ws_accept_key;
///
/// assert!(ws_accept_key("dGhlIHNhbXBsZSBub25jZQ==") == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=");
/// ```
fn ws_accept_key(string key) -> string {
    let raw = concat_bytes(to_bytes(key), to_bytes(ws_guid()));
    return encode(sha1(raw));
}

/// 1 when `req` is a WebSocket upgrade: `GET` with `Upgrade: websocket`,
/// `Connection: upgrade`, `Sec-WebSocket-Version: 13` and a
/// `Sec-WebSocket-Key`; otherwise 0.
fn ws_is_upgrade_req(IncomingRequest req) -> int {
    if req.method_val() != "GET" {
        return 0;
    }
    if ws_contains_ci(ws_header_get_req(req, "Upgrade"), "websocket") == 0 {
        return 0;
    }
    if ws_contains_ci(ws_header_get_req(req, "Connection"), "upgrade") == 0 {
        return 0;
    }
    if ws_header_get_req(req, "Sec-WebSocket-Version") != "13" {
        return 0;
    }
    if ws_header_get_req(req, "Sec-WebSocket-Key") == "" {
        return 0;
    }
    return 1;
}

fn ws_host_hdr(Url u) -> string {
    let host = u.host;
    let port = u.port;
    let scheme = u.scheme;
    if scheme == "ws" {
        if port == 80 {
            return host;
        }
    }
    if scheme == "http" {
        if port == 80 {
            return host;
        }
    }
    if scheme == "wss" {
        if port == 443 {
            return host;
        }
    }
    if scheme == "https" {
        if port == 443 {
            return host;
        }
    }
    return host + ":" + int_to_dec(port);
}

fn build_ws_upgrade_request(Url u, string key) -> Vec<byte> {
    let s = "GET " + u.path + " HTTP/1.1\r\nHost: " + ws_host_hdr(u) + "\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: " + key + "\r\nSec-WebSocket-Version: 13\r\n\r\n";
    return to_bytes(s);
}

fn encode_ws_upgrade_response(string accept) -> Vec<byte> {
    let s = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept + "\r\n\r\n";
    return to_bytes(s);
}

fn ws_prng_bytes(int n, int seed) -> Vec<byte> {
    let x = seed;
    if x == 0 {
        x = 1;
    }
    let out: Vec<byte> = Vec::new();
    let i = 0;
    while i < n {
        x = (x * 1664525 + 1013904223) % (ws_b24() * ws_mod256());
        out.push(ws_u8(x));
        i = i + 1;
    }
    return out;
}

/// A `Sec-WebSocket-Key`: 16 bytes from a simple generator seeded with `seed`,
/// Base64-encoded. Not cryptographically random.
fn ws_new_key(int seed) -> string {
    return encode(ws_prng_bytes(16, seed));
}

fn ws_next_mask(WsConn c) -> Vec<byte> {
    c.seed = (c.seed * 1664525 + 1013904223) % (ws_b24() * ws_mod256());
    return ws_prng_bytes(4, c.seed);
}

fn ws_write(WsConn c, Vec<byte> wire) -> Result<(), HttpError> {
    match write_all(c.conn.stream(), wire) {
        Result::Ok(_) => 0,
        Result::Err(e) => {
            http_fail_unit(e)?;
            0
        },
    };
    return ();
}

fn ws_send_raw(WsConn c, int opcode, Vec<byte> payload) -> Result<(), HttpError> {
    let key: Vec<byte> = Vec::new();
    if c.role == 1 {
        key = ws_next_mask(c);
    }
    return ws_write(c, encode_ws_frame(1, opcode, key, payload))?;
}

/// Sends `s` as one text frame.
fn ws_send_text(WsConn c, string s) -> Result<(), HttpError> {
    return ws_send_raw(c, ws_opcode_text(), to_bytes(s))?;
}

/// Sends `b` as one binary frame.
fn ws_send_bin(WsConn c, Vec<byte> b) -> Result<(), HttpError> {
    return ws_send_raw(c, ws_opcode_bin(), b)?;
}

/// Sends a ping with payload `b` (RFC 6455 allows at most 125 bytes; not checked).
fn ws_send_ping(WsConn c, Vec<byte> b) -> Result<(), HttpError> {
    return ws_send_raw(c, ws_opcode_ping(), b)?;
}

/// Sends a pong with payload `b`, normally the payload of the ping it answers.
fn ws_send_pong(WsConn c, Vec<byte> b) -> Result<(), HttpError> {
    return ws_send_raw(c, ws_opcode_pong(), b)?;
}

/// Sends a close frame with no status code. Call `ws_close` afterwards.
fn ws_send_close(WsConn c) -> Result<(), HttpError> {
    let empty: Vec<byte> = Vec::new();
    return ws_send_raw(c, ws_opcode_close(), empty)?;
}

// Blocking read that parks on WouldBlock (same pattern as HTTP/2).
fn ws_read_n(HttpConn c, int n) -> Result<Vec<byte>, HttpError> {
    let out: Vec<byte> = Vec::new();
    let have = c.leftover.len();
    let take = n;
    if take > have {
        take = have;
    }
    let i = 0;
    while i < take {
        out.push(c.leftover[i]);
        i = i + 1;
    }
    if take < have {
        let rest: Vec<byte> = Vec::new();
        let j = take;
        while j < have {
            rest.push(c.leftover[j]);
            j = j + 1;
        }
        c.leftover = rest;
    } else {
        let empty: Vec<byte> = Vec::new();
        c.leftover = empty;
    }
    let need = n - out.len();
    if need == 0 {
        return out;
    }
    let s = c.stream();
    let filled = 0;
    while filled < need {
        let scratch: Vec<byte> = Vec::new();
        let k = 0;
        while k < need - filled {
            scratch.push(0);
            k = k + 1;
        }
        match read(s, scratch) {
            Result::Ok(opt) => {
                match opt {
                    Option::None => {
                        http_err_protocol()?;
                    },
                    Option::Some(got) => {
                        if got == 0 {
                            match wait_readable(s) {
                                Result::Ok(_) => 0,
                                Result::Err(e) => {
                                    http_err_io(e)?;
                                    0
                                },
                            };
                        }
                        if got != 0 {
                            let p = 0;
                            while p < got {
                                out.push(scratch[p]);
                                p = p + 1;
                            }
                            filled = filled + got;
                        }
                    },
                };
                0
            },
            Result::Err(IoError::WouldBlock) => {
                match wait_readable(s) {
                    Result::Ok(_) => 0,
                    Result::Err(e) => {
                        http_err_io(e)?;
                        0
                    },
                };
                0
            },
            Result::Err(e) => {
                http_err_io(e)?;
                0
            },
        };
    }
    return out;
}

fn ws_read_frame(WsConn c) -> Result<WsFrame, HttpError> {
    let hdr = ws_read_n(c.conn, 2)?;
    let need = ws_frame_wire_len(hdr);
    if need == 0 {
        let b1 = ws_u8_at(hdr, 1);
        let llen = b1 & 127;
        let extra = 0;
        if llen == 126 {
            extra = 2;
        }
        if llen == 127 {
            extra = 8;
        }
        if extra > 0 {
            let ext = ws_read_n(c.conn, extra)?;
            hdr = concat_bytes(hdr, ext);
        }
        let masked = (ws_u8_at(hdr, 1) >> 7) & 1;
        if masked == 1 {
            let mk = ws_read_n(c.conn, 4)?;
            hdr = concat_bytes(hdr, mk);
        }
        let n = 0;
        let llen2 = ws_u8_at(hdr, 1) & 127;
        if llen2 < 126 {
            n = llen2;
        } else {
            if llen2 == 126 {
                n = ws_u8_at(hdr, 2) * ws_mod256() + ws_u8_at(hdr, 3);
            } else {
                n = ws_u8_at(hdr, 6) * ws_b24() + ws_u8_at(hdr, 7) * ws_b16() + ws_u8_at(hdr, 8) * ws_mod256() + ws_u8_at(hdr, 9);
            }
        }
        if n > ws_max_payload() {
            http_err_protocol()?;
        }
        let body = ws_read_n(c.conn, n)?;
        return decode_ws_frame(concat_bytes(hdr, body))?;
    }
    if need > 2 {
        let rest = ws_read_n(c.conn, need - 2)?;
        hdr = concat_bytes(hdr, rest);
    }
    return decode_ws_frame(hdr)?;
}

/// Reads the next complete frame. Waits while no data is ready.
///
/// Returns `Protocol` for a fragment (`fin` 0), for a masked frame on a client
/// or an unmasked one on a server, and for the cases `decode_ws_frame` rejects.
fn ws_recv(WsConn c) -> Result<WsFrame, HttpError> {
    let f = ws_read_frame(c)?;
    if c.role == 1 {
        if f.masked == 1 {
            http_err_protocol()?;
        }
    } else {
        if f.masked == 0 {
            http_err_protocol()?;
        }
    }
    if f.fin == 0 {
        http_err_protocol()?;
    }
    return f;
}

/// Closes the connection. Closing twice does nothing.
fn ws_close(WsConn c) {
    if c.closed == 1 {
        return;
    }
    c.closed = 1;
    close_conn(c.conn);
}

fn ws_wrap(HttpConn conn, int role, int seed) -> WsConn {
    return new WsConn(conn, role, 0, seed);
}

fn ws_check_upgrade_resp(Response r, string key) -> Result<(), HttpError> {
    if r.status != 101 {
        http_err_protocol()?;
    }
    if ws_contains_ci(ws_header_get_resp(r, "Upgrade"), "websocket") == 0 {
        http_err_protocol()?;
    }
    if ws_contains_ci(ws_header_get_resp(r, "Connection"), "upgrade") == 0 {
        http_err_protocol()?;
    }
    let got = ws_header_get_resp(r, "Sec-WebSocket-Accept");
    if got != ws_accept_key(key) {
        http_err_protocol()?;
    }
    return ();
}

fn ws_open_stream(Url u, bool verify, string ca_pem) -> Result<Stream, HttpError> {
    let scheme = u.scheme;
    let host = u.host;
    let port = u.port;
    if scheme == "ws" {
        return match tcp_connect(host, port) {
            Result::Ok(s) => s,
            Result::Err(e) => http_fail_stream(e)?,
        };
    }
    if scheme == "wss" {
        let s = match tcp_connect(host, port) {
            Result::Ok(v) => v,
            Result::Err(e) => http_fail_stream(e)?,
        };
        let ca = Option::None;
        if ca_pem != "" {
            ca = Option::Some(ca_pem);
        }
        return match tls_enable(s, host, new ClientOpts(verify, ca, Option::None, 5000, "")) {
            Result::Ok(v) => v,
            Result::Err(e) => {
                match io_close(s) {
                    Result::Ok(_) => 0,
                    Result::Err(_) => 0,
                };
                http_fail_tls(e)?
            },
        };
    }
    raise HttpError::UnsupportedScheme;
}

fn ws_handshake_client(HttpConn c, Url u, string key) -> Result<WsConn, HttpError> {
    match write_all(c.stream(), build_ws_upgrade_request(u, key)) {
        Result::Ok(_) => 0,
        Result::Err(e) => {
            close_conn(c);
            http_fail_unit(e)?;
            0
        },
    };
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
    match ws_check_upgrade_resp(resp, key) {
        Result::Ok(_) => 0,
        Result::Err(e) => {
            close_conn(c);
            raise e;
        },
    };
    return ws_wrap(c, 1, 17 + u.port);
}

/// Opens a WebSocket to a `ws://` or `wss://` URL with TLS options.
///
/// For `wss://`, `verify` false skips certificate checks and a non-empty
/// `ca_pem` trusts that PEM CA; both are ignored for `ws://`. Returns `BadUrl` for
/// other schemes, `Io` / `Tls` when connecting fails and `Protocol` when the
/// server does not accept the upgrade.
fn ws_connect_tls(string url, bool verify, string ca_pem) -> Result<WsConn, HttpError> {
    let u = parse_url(url)?;
    if u.scheme != "ws" {
        if u.scheme != "wss" {
            http_err_bad_url()?;
        }
    }
    let s = ws_open_stream(u, verify, ca_pem)?;
    let key = ws_new_key(to_bytes(url).len() * 33 + u.port);
    return ws_handshake_client(HttpConn::wrap(s), u, key)?;
}

/// Opens a WebSocket to a `ws://` or `wss://` URL (`wss://` with verified TLS).
///
/// Sends the HTTP/1.1 upgrade request and checks the server's
/// `Sec-WebSocket-Accept`. Errors are as for `ws_connect_tls`.
fn ws_connect(string url) -> Result<WsConn, HttpError> {
    return ws_connect_tls(url, true, "")?;
}

/// `ws_connect` with a caller-supplied `Sec-WebSocket-Key`, for tests against a known handshake.
fn ws_connect_key(string url, string key) -> Result<WsConn, HttpError> {
    let u = parse_url(url)?;
    if u.scheme != "ws" {
        if u.scheme != "wss" {
            http_err_bad_url()?;
        }
    }
    let s = ws_open_stream(u, true, "")?;
    return ws_handshake_client(HttpConn::wrap(s), u, key)?;
}

/// Completes the server side of an upgrade for a request already read from `c`.
///
/// Writes `101 Switching Protocols` and returns the server `WsConn`. Returns
/// `Protocol` when `req` is not an upgrade (see `ws_is_upgrade_req`).
fn ws_upgrade(HttpConn c, IncomingRequest req) -> Result<WsConn, HttpError> {
    if ws_is_upgrade_req(req) == 0 {
        http_err_protocol()?;
    }
    let key = ws_header_get_req(req, "Sec-WebSocket-Key");
    let accept = ws_accept_key(key);
    match write_all(c.stream(), encode_ws_upgrade_response(accept)) {
        Result::Ok(_) => 0,
        Result::Err(e) => {
            close_conn(c);
            http_fail_unit(e)?;
            0
        },
    };
    return ws_wrap(c, 0, 91);
}

/// Accepts one connection on `srv`, reads its HTTP/1.1 request and completes the
/// WebSocket upgrade.
///
/// Cleartext only: `Server::tls` is not applied here. Returns `Io(InvalidInput)`
/// when `srv` is not bound and `Protocol` when the request is not an upgrade.
///
/// # Examples
///
/// ```no_run
/// use http::server::Server;
/// use http::ws::{ws_echo_loop, ws_serve_once};
/// use http::url::HttpError;
///
/// fn main() -> Result<(), HttpError> {
///     let srv = Server::new();
///     srv.bind("127.0.0.1", 8080)?;
///     let c = ws_serve_once(srv)?;
///     ws_echo_loop(c)?;
///     return ();
/// }
/// ```
fn ws_serve_once(Server srv) -> Result<WsConn, HttpError> {
    let listener = match srv.listener {
        Option::None => http_not_bound()?,
        Option::Some(s) => s,
    };
    let conn = match accept_wait(listener) {
        Result::Ok(s) => s,
        Result::Err(e) => http_fail_stream(e)?,
    };
    let c = HttpConn::wrap(conn);
    let raw = match read_http_message(c) {
        Result::Ok(b) => b,
        Result::Err(e) => {
            close_conn(c);
            raise e;
        },
    };
    let req = match parse_request(raw) {
        Result::Ok(r) => r,
        Result::Err(e) => {
            close_conn(c);
            raise e;
        },
    };
    return ws_upgrade(c, req)?;
}

/// Echoes text and binary frames, answers pings with pongs, and returns after
/// answering a close frame or on the first error, closing the connection.
fn ws_echo_loop(WsConn c) -> Result<(), HttpError> {
    let keep = 1;
    while keep == 1 {
        let f = match ws_recv(c) {
            Result::Ok(v) => v,
            Result::Err(_) => {
                keep = 0;
                let empty: Vec<byte> = Vec::new();
                WsFrame::new(1, 8, 0, empty)
            },
        };
        if keep == 1 {
            if f.opcode == ws_opcode_ping() {
                match ws_send_pong(c, f.payload) {
                    Result::Ok(_) => 0,
                    Result::Err(_) => {
                        keep = 0;
                        0
                    },
                };
            } else {
                if f.opcode == ws_opcode_text() {
                    match ws_send_raw(c, ws_opcode_text(), f.payload) {
                        Result::Ok(_) => 0,
                        Result::Err(_) => {
                            keep = 0;
                            0
                        },
                    };
                } else {
                    if f.opcode == ws_opcode_bin() {
                        match ws_send_raw(c, ws_opcode_bin(), f.payload) {
                            Result::Ok(_) => 0,
                            Result::Err(_) => {
                                keep = 0;
                                0
                            },
                        };
                    } else {
                        if f.opcode == ws_opcode_close() {
                            match ws_send_close(c) {
                                Result::Ok(_) => 0,
                                Result::Err(_) => 0,
                            };
                            keep = 0;
                        }
                    }
                }
            }
        }
    }
    ws_close(c);
    return ();
}
