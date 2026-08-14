// HTTP/2 framing (RFC 7540 §4). HPACK static table is in http::hpack; mux is still NotSupported on the wire.
use http::url::{HttpError, http_err_bad_response, http_err_not_supported};
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
    // Clear RFC 7540 reserved bit (bit 31). Compute 2^31 — a 2147483648 literal is unreliable in Coil.
    let two31 = 128 * 16777216;
    sid = sid % two31;
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
