// WebSocket (RFC 6455) over HTTP/1.1 upgrade. Framing + handshake; not a new transport.
use encoding::{encode};
use conv::{int_to_dec};
use io::{Stream, close as io_close, to_bytes, read, IoError, await_readable};
use io::net::tcp::connect as tcp_connect;
use io::sync::{accept_wait, write_all};
use tls::client::{enable as tls_enable, ClientOpts};
use http::sha1::{sha1};
use http::url::{
    HttpError,
    Url,
    header_name_eq_ci,
    http_err_bad_response,
    http_err_bad_url,
    http_err_io,
    http_err_unsupported_scheme,
    http_fail_stream,
    http_fail_unit,
    parse_url,
};
use http::h1::{IncomingRequest, parse_request};
use http::request::{concat_bytes};
use http::response::{Response, bytes_slice_resp, header_get, parse_response};
use http::conn::{HttpConn, close_conn, read_http_message};
use http::server::{Server};

class WsFrame {
    fin: int,
    opcode: int,
    masked: int,
    payload: Vec<byte>,
}

impl WsFrame {
    static fn new(int fin, int opcode, int masked, Vec<byte> payload) -> WsFrame {
        return new WsFrame(fin, opcode, masked, payload);
    }
}

/// Upgraded WebSocket on an HTTP/1.1 connection. `role` 1 = client (mask outbound).
class WsConn {
    conn: HttpConn,
    role: int,
    closed: int,
    seed: int,
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

fn ws_opcode_cont() -> int {
    return 0;
}

fn ws_opcode_text() -> int {
    return 1;
}

fn ws_opcode_bin() -> int {
    return 2;
}

fn ws_opcode_close() -> int {
    return 8;
}

fn ws_opcode_ping() -> int {
    return 9;
}

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
    while i < len(payload) {
        let x = (payload[i] as int) ^ (key[i % 4] as int);
        out.push(ws_u8(x));
        i = i + 1;
    }
    return out;
}

fn ws_max_payload() -> int {
    return 1048576;
}

/// Encode one frame. `mask_key` length 4 masks the payload; empty means unmasked.
fn encode_ws_frame(int fin, int opcode, Vec<byte> mask_key, Vec<byte> payload) -> Vec<byte> {
    let out: Vec<byte> = Vec::new();
    let b0 = opcode & 15;
    if fin == 1 {
        b0 = b0 | 128;
    }
    ws_push_u8(out, b0);
    let n = len(payload);
    let masked = 0;
    if len(mask_key) == 4 {
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
    while j < len(data) {
        out.push(data[j]);
        j = j + 1;
    }
    return out;
}

fn ws_u8_at(Vec<byte> raw, int i) -> int {
    return raw[i] as int;
}

/// Parse the first complete WebSocket frame in `raw`. Extra bytes after it are ignored.
fn decode_ws_frame(Vec<byte> raw) -> Result<WsFrame, HttpError> {
    if len(raw) < 2 {
        http_err_bad_response()?;
    }
    let b0 = ws_u8_at(raw, 0);
    let b1 = ws_u8_at(raw, 1);
    let rsv = (b0 >> 4) & 7;
    if rsv != 0 {
        http_err_bad_response()?;
    }
    let fin = (b0 >> 7) & 1;
    let opcode = b0 & 15;
    let masked = (b1 >> 7) & 1;
    let llen = b1 & 127;
    let pos = 2;
    let n = llen;
    if llen == 126 {
        if len(raw) < 4 {
            http_err_bad_response()?;
        }
        n = ws_u8_at(raw, 2) * ws_mod256() + ws_u8_at(raw, 3);
        pos = 4;
    }
    if llen == 127 {
        if len(raw) < 10 {
            http_err_bad_response()?;
        }
        if ws_u8_at(raw, 2) != 0 {
            http_err_bad_response()?;
        }
        if ws_u8_at(raw, 3) != 0 {
            http_err_bad_response()?;
        }
        if ws_u8_at(raw, 4) != 0 {
            http_err_bad_response()?;
        }
        if ws_u8_at(raw, 5) != 0 {
            http_err_bad_response()?;
        }
        n = ws_u8_at(raw, 6) * ws_b24() + ws_u8_at(raw, 7) * ws_b16() + ws_u8_at(raw, 8) * ws_mod256() + ws_u8_at(raw, 9);
        pos = 10;
    }
    if n > ws_max_payload() {
        http_err_bad_response()?;
    }
    let key: Vec<byte> = Vec::new();
    if masked == 1 {
        if len(raw) < pos + 4 {
            http_err_bad_response()?;
        }
        key.push(raw[pos]);
        key.push(raw[pos + 1]);
        key.push(raw[pos + 2]);
        key.push(raw[pos + 3]);
        pos = pos + 4;
    }
    if len(raw) < pos + n {
        http_err_bad_response()?;
    }
    let payload = bytes_slice_resp(raw, pos, pos + n);
    if masked == 1 {
        payload = ws_mask_apply(payload, key);
    }
    return WsFrame::new(fin, opcode, masked, payload);
}

/// Byte count of the first complete frame, or 0 if truncated.
fn ws_frame_wire_len(Vec<byte> raw) -> int {
    if len(raw) < 2 {
        return 0;
    }
    let b1 = ws_u8_at(raw, 1);
    let masked = (b1 >> 7) & 1;
    let llen = b1 & 127;
    let extra = 0;
    let n = llen;
    if llen == 126 {
        if len(raw) < 4 {
            return 0;
        }
        extra = 2;
        n = ws_u8_at(raw, 2) * ws_mod256() + ws_u8_at(raw, 3);
    }
    if llen == 127 {
        if len(raw) < 10 {
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
    if len(raw) < total {
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
    if len(nb) == 0 {
        return 1;
    }
    if len(nb) > len(hb) {
        return 0;
    }
    let i = 0;
    while i + len(nb) <= len(hb) {
        let ok = 1;
        let j = 0;
        while j < len(nb) {
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
    while i < len(h.names) {
        if header_name_eq_ci(h.names[i], name) == 1 {
            return h.values[i];
        }
        i = i + 1;
    }
    return "";
}

fn ws_header_get_resp(Response r, string name) -> string {
    let i = 0;
    while i < len(r.header_names) {
        if header_name_eq_ci(r.header_names[i], name) == 1 {
            return r.header_values[i];
        }
        i = i + 1;
    }
    let v = header_get(r, name);
    return v;
}

/// SHA-1(key + GUID) then Base64 — `Sec-WebSocket-Accept`.
fn ws_accept_key(string key) -> string {
    let raw = concat_bytes(to_bytes(key), to_bytes(ws_guid()));
    return encode(sha1(raw));
}

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

/// 16 random-ish bytes as standard Base64 (`Sec-WebSocket-Key`).
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
        Result::Err(_) => {
            http_fail_unit()?;
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

fn ws_send_text(WsConn c, string s) -> Result<(), HttpError> {
    return ws_send_raw(c, ws_opcode_text(), to_bytes(s))?;
}

fn ws_send_bin(WsConn c, Vec<byte> b) -> Result<(), HttpError> {
    return ws_send_raw(c, ws_opcode_bin(), b)?;
}

fn ws_send_ping(WsConn c, Vec<byte> b) -> Result<(), HttpError> {
    return ws_send_raw(c, ws_opcode_ping(), b)?;
}

fn ws_send_pong(WsConn c, Vec<byte> b) -> Result<(), HttpError> {
    return ws_send_raw(c, ws_opcode_pong(), b)?;
}

fn ws_send_close(WsConn c) -> Result<(), HttpError> {
    let empty: Vec<byte> = Vec::new();
    return ws_send_raw(c, ws_opcode_close(), empty)?;
}

/// Blocking read that parks on WouldBlock (same pattern as HTTP/2).
fn ws_read_n(HttpConn c, int n) -> Result<Vec<byte>, HttpError> {
    let out: Vec<byte> = Vec::new();
    let have = len(c.leftover);
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
    let need = n - len(out);
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
            http_err_bad_response()?;
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

/// Read one frame. Client rejects masked frames; server rejects unmasked data/control.
fn ws_recv(WsConn c) -> Result<WsFrame, HttpError> {
    let f = ws_read_frame(c)?;
    if c.role == 1 {
        if f.masked == 1 {
            http_err_bad_response()?;
        }
    } else {
        if f.masked == 0 {
            http_err_bad_response()?;
        }
    }
    if f.fin == 0 {
        http_err_bad_response()?;
    }
    return f;
}

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
        http_err_bad_response()?;
    }
    if ws_contains_ci(ws_header_get_resp(r, "Upgrade"), "websocket") == 0 {
        http_err_bad_response()?;
    }
    if ws_contains_ci(ws_header_get_resp(r, "Connection"), "upgrade") == 0 {
        http_err_bad_response()?;
    }
    let got = ws_header_get_resp(r, "Sec-WebSocket-Accept");
    if got != ws_accept_key(key) {
        http_err_bad_response()?;
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
            Result::Err(_) => http_fail_stream()?,
        };
    }
    if scheme == "wss" {
        let s = match tcp_connect(host, port) {
            Result::Ok(v) => v,
            Result::Err(_) => http_fail_stream()?,
        };
        let ca = Option::None;
        if ca_pem != "" {
            ca = Option::Some(ca_pem);
        }
        return match tls_enable(s, host, new ClientOpts(verify, ca, Option::None, 5000, "")) {
            Result::Ok(v) => v,
            Result::Err(_) => {
                match io_close(s) {
                    Result::Ok(_) => 0,
                    Result::Err(_) => 0,
                };
                http_fail_stream()?
            },
        };
    }
    http_err_unsupported_scheme()?;
    return http_fail_stream()?;
}

fn ws_handshake_client(HttpConn c, Url u, string key) -> Result<WsConn, HttpError> {
    match write_all(c.stream(), build_ws_upgrade_request(u, key)) {
        Result::Ok(_) => 0,
        Result::Err(_) => {
            close_conn(c);
            http_fail_unit()?;
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

/// Client upgrade with TLS options (`verify` / optional CA PEM). `ws://` ignores TLS args.
fn ws_connect_tls(string url, bool verify, string ca_pem) -> Result<WsConn, HttpError> {
    let u = parse_url(url)?;
    if u.scheme != "ws" {
        if u.scheme != "wss" {
            http_err_bad_url()?;
        }
    }
    let s = ws_open_stream(u, verify, ca_pem)?;
    let key = ws_new_key(len(to_bytes(url)) * 33 + u.port);
    return ws_handshake_client(HttpConn::wrap(s), u, key)?;
}

/// Client upgrade. `ws://` is cleartext; `wss://` uses coil-tls (verified).
fn ws_connect(string url) -> Result<WsConn, HttpError> {
    return ws_connect_tls(url, true, "")?;
}

/// Client upgrade with a caller-supplied `Sec-WebSocket-Key` (tests / RFC vector).
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

fn ws_upgrade(HttpConn c, IncomingRequest req) -> Result<WsConn, HttpError> {
    if ws_is_upgrade_req(req) == 0 {
        http_err_bad_response()?;
    }
    let key = ws_header_get_req(req, "Sec-WebSocket-Key");
    let accept = ws_accept_key(key);
    match write_all(c.stream(), encode_ws_upgrade_response(accept)) {
        Result::Ok(_) => 0,
        Result::Err(_) => {
            close_conn(c);
            http_fail_unit()?;
            0
        },
    };
    return ws_wrap(c, 0, 91);
}

/// Accept one TCP connection, read an HTTP/1.1 upgrade, return the WebSocket.
fn ws_serve_once(Server srv) -> Result<WsConn, HttpError> {
    let listener = match srv.listener {
        Option::None => http_fail_stream()?,
        Option::Some(s) => s,
    };
    let conn = match accept_wait(listener) {
        Result::Ok(s) => s,
        Result::Err(_) => http_fail_stream()?,
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

/// Echo text/binary, answer ping, stop on close. Used by loopback examples.
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
