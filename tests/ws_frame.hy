// RFC 6455 §5.7 frame encode/decode (no sockets).
use string::{to_bytes};
use http::url::{HttpError};
use http::ws::{
    WsFrame,
    decode_ws_frame,
    encode_ws_frame,
    ws_frame_wire_len,
    ws_opcode_bin,
    ws_opcode_close,
    ws_opcode_cont,
    ws_opcode_ping,
    ws_opcode_pong,
    ws_opcode_text,
};

fn push_u(Vec<byte> v, int n) {
    v.push(n as byte);
}

test("unmasked hello text") {
    let empty: Vec<byte> = Vec::new();
    let wire = encode_ws_frame(1, ws_opcode_text(), empty, to_bytes("Hello"));
    assert(len(wire) == 7, "len")?;
    assert(wire[0] as int == 129, "fin text")?;
    assert(wire[1] as int == 5, "unmasked len")?;
    let f = match decode_ws_frame(wire) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode",
    };
    assert(f.fin == 1, "fin")?;
    assert(f.opcode == 1, "opcode")?;
    assert(f.masked == 0, "mask")?;
    assert(len(f.payload) == 5, "payload")?;
    assert(f.payload[0] as int == 72, "H")?;
}

test("masked hello rfc 6455") {
    let key: Vec<byte> = Vec::new();
    push_u(key, 55);
    push_u(key, 250);
    push_u(key, 33);
    push_u(key, 61);
    let wire = encode_ws_frame(1, ws_opcode_text(), key, to_bytes("Hello"));
    assert(len(wire) == 11, "masked len")?;
    assert(wire[0] as int == 129, "fin text")?;
    assert(wire[1] as int == 133, "mask+5")?;
    assert(wire[2] as int == 55, "k0")?;
    assert(wire[6] as int == 127, "p0")?;
    assert(wire[7] as int == 159, "p1")?;
    assert(wire[8] as int == 77, "p2")?;
    assert(wire[9] as int == 81, "p3")?;
    assert(wire[10] as int == 88, "p4")?;
    let f = match decode_ws_frame(wire) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode masked",
    };
    assert(f.masked == 1, "masked")?;
    assert(len(f.payload) == 5, "unmasked payload")?;
    assert(f.payload[0] as int == 72, "H")?;
    assert(f.payload[4] as int == 111, "o")?;
}

test("extended 16-bit length") {
    let payload: Vec<byte> = Vec::new();
    let i = 0;
    while i < 256 {
        payload.push(65);
        i = i + 1;
    }
    let empty: Vec<byte> = Vec::new();
    let wire = encode_ws_frame(1, ws_opcode_bin(), empty, payload);
    assert(wire[1] as int == 126, "126")?;
    assert(len(wire) == 4 + 256, "ext16")?;
    let f = match decode_ws_frame(wire) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode 16",
    };
    assert(len(f.payload) == 256, "payload 256")?;
    assert(ws_frame_wire_len(wire) == len(wire), "wire len")?;
}

test("ping opcode") {
    let empty: Vec<byte> = Vec::new();
    let wire = encode_ws_frame(1, ws_opcode_ping(), empty, to_bytes("Hello"));
    assert(wire[0] as int == 137, "fin ping")?;
    let f = match decode_ws_frame(wire) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode ping",
    };
    assert(f.opcode == 9, "ping")?;
}

test("reject rsv bits") {
    let raw: Vec<byte> = Vec::new();
    push_u(raw, 193);
    push_u(raw, 0);
    let r = decode_ws_frame(raw);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "rsv")?;
}

fn fill_bytes(int n, int v) -> Vec<byte> {
    let out: Vec<byte> = Vec::new();
    let i = 0;
    while i < n {
        out.push(v as byte);
        i = i + 1;
    }
    return out;
}

fn is_err_frame(Result<WsFrame, HttpError> r) -> bool {
    return match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    };
}

test("pong opcode unmasked") {
    let empty: Vec<byte> = Vec::new();
    let wire = encode_ws_frame(1, ws_opcode_pong(), empty, to_bytes("Hello"));
    assert(wire[0] as int == 138, "fin pong")?;
    assert(wire[1] as int == 5, "server no mask")?;
    let f = match decode_ws_frame(wire) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode pong",
    };
    assert(f.opcode == 10, "pong")?;
    assert(f.masked == 0, "unmasked")?;
    assert(len(f.payload) == 5, "echo")?;
    assert(f.payload[0] as int == 72, "H")?;
}

test("close empty and code 1000") {
    let empty: Vec<byte> = Vec::new();
    let wire = encode_ws_frame(1, ws_opcode_close(), empty, empty);
    assert(wire[0] as int == 136, "fin close")?;
    assert(wire[1] as int == 0, "empty unmasked")?;
    let f = match decode_ws_frame(wire) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode close empty",
    };
    assert(f.opcode == 8, "close")?;
    assert(len(f.payload) == 0, "no reason")?;
    let code: Vec<byte> = Vec::new();
    push_u(code, 3);
    push_u(code, 232);
    let keyed: Vec<byte> = Vec::new();
    push_u(keyed, 1);
    push_u(keyed, 2);
    push_u(keyed, 3);
    push_u(keyed, 4);
    let cwire = encode_ws_frame(1, ws_opcode_close(), keyed, code);
    assert(cwire[1] as int == 130, "mask+2")?;
    let g = match decode_ws_frame(cwire) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode close 1000",
    };
    assert(g.opcode == 8, "opcode")?;
    assert(g.masked == 1, "client mask")?;
    assert(len(g.payload) == 2, "code bytes")?;
    assert(g.payload[0] as int == 3, "1000 hi")?;
    assert(g.payload[1] as int == 232, "1000 lo")?;
}

test("binary unmasked vs masked") {
    let empty: Vec<byte> = Vec::new();
    let body = to_bytes("bin");
    let server = encode_ws_frame(1, ws_opcode_bin(), empty, body);
    assert(server[0] as int == 130, "fin bin")?;
    assert(server[1] as int == 3, "server no mask")?;
    let s = match decode_ws_frame(server) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "server bin",
    };
    assert(s.opcode == 2, "bin")?;
    assert(s.masked == 0, "unmasked")?;
    assert(s.payload[0] as int == 98, "b")?;
    let key: Vec<byte> = Vec::new();
    push_u(key, 10);
    push_u(key, 20);
    push_u(key, 30);
    push_u(key, 40);
    let client = encode_ws_frame(1, ws_opcode_bin(), key, body);
    assert(client[1] as int == 131, "client mask+3")?;
    let c = match decode_ws_frame(client) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "client bin",
    };
    assert(c.masked == 1, "masked")?;
    assert(c.payload[0] as int == 98, "b")?;
    assert(c.payload[1] as int == 105, "i")?;
    assert(c.payload[2] as int == 110, "n")?;
}

test("7-bit max and 16-bit min lengths") {
    let empty: Vec<byte> = Vec::new();
    let p125 = fill_bytes(125, 65);
    let w125 = encode_ws_frame(1, ws_opcode_text(), empty, p125);
    assert(w125[1] as int == 125, "7-bit")?;
    assert(len(w125) == 2 + 125, "no ext")?;
    let f125 = match decode_ws_frame(w125) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "125",
    };
    assert(len(f125.payload) == 125, "payload 125")?;
    assert(ws_frame_wire_len(w125) == len(w125), "wire 125")?;
    let p126 = fill_bytes(126, 66);
    let w126 = encode_ws_frame(1, ws_opcode_text(), empty, p126);
    assert(w126[1] as int == 126, "16-bit form")?;
    assert(w126[2] as int == 0, "len hi")?;
    assert(w126[3] as int == 126, "len lo")?;
    assert(len(w126) == 4 + 126, "ext16")?;
    let f126 = match decode_ws_frame(w126) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "126",
    };
    assert(len(f126.payload) == 126, "payload 126")?;
}

test("64-bit length form") {
    let empty: Vec<byte> = Vec::new();
    let n = 65536;
    let payload = fill_bytes(n, 67);
    let wire = encode_ws_frame(1, ws_opcode_bin(), empty, payload);
    assert(wire[1] as int == 127, "127")?;
    assert(wire[2] as int == 0, "b2")?;
    assert(wire[7] as int == 1, "65536 hi")?;
    assert(wire[8] as int == 0, "mid")?;
    assert(wire[9] as int == 0, "lo")?;
    assert(len(wire) == 10 + n, "ext64")?;
    let f = match decode_ws_frame(wire) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode 64",
    };
    assert(len(f.payload) == n, "payload 64k")?;
    assert(f.payload[0] as int == 67, "first")?;
    assert(f.payload[n - 1] as int == 67, "last")?;
    assert(ws_frame_wire_len(wire) == len(wire), "wire 64")?;
    let key: Vec<byte> = Vec::new();
    push_u(key, 9);
    push_u(key, 8);
    push_u(key, 7);
    push_u(key, 6);
    let masked = encode_ws_frame(1, ws_opcode_bin(), key, payload);
    assert(masked[1] as int == 255, "mask+127")?;
    assert(len(masked) == 14 + n, "mask+ext64")?;
    let g = match decode_ws_frame(masked) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode masked 64",
    };
    assert(g.masked == 1, "masked")?;
    assert(len(g.payload) == n, "unmasked 64k")?;
    assert(g.payload[0] as int == 67, "C")?;
}

test("fin zero continuation opcode") {
    let empty: Vec<byte> = Vec::new();
    let wire = encode_ws_frame(0, ws_opcode_cont(), empty, to_bytes("ab"));
    assert(wire[0] as int == 0, "no fin cont")?;
    let f = match decode_ws_frame(wire) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "cont",
    };
    assert(f.fin == 0, "fin")?;
    assert(f.opcode == 0, "cont")?;
    assert(len(f.payload) == 2, "ab")?;
}

test("decode ignores trailing bytes") {
    let empty: Vec<byte> = Vec::new();
    let wire = encode_ws_frame(1, ws_opcode_text(), empty, to_bytes("Hi"));
    wire.push(88);
    wire.push(89);
    let f = match decode_ws_frame(wire) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "trailer",
    };
    assert(len(f.payload) == 2, "payload")?;
    assert(ws_frame_wire_len(wire) == 4, "first frame only")?;
}

test("reject truncated and short payload") {
    let empty: Vec<byte> = Vec::new();
    assert(is_err_frame(decode_ws_frame(empty)), "empty")?;
    let one: Vec<byte> = Vec::new();
    push_u(one, 129);
    assert(is_err_frame(decode_ws_frame(one)), "one byte")?;
    let hdr: Vec<byte> = Vec::new();
    push_u(hdr, 129);
    push_u(hdr, 5);
    push_u(hdr, 65);
    assert(is_err_frame(decode_ws_frame(hdr)), "short payload")?;
    let ext: Vec<byte> = Vec::new();
    push_u(ext, 130);
    push_u(ext, 126);
    push_u(ext, 0);
    assert(is_err_frame(decode_ws_frame(ext)), "short ext16")?;
    let e64: Vec<byte> = Vec::new();
    push_u(e64, 130);
    push_u(e64, 127);
    push_u(e64, 0);
    push_u(e64, 0);
    push_u(e64, 0);
    assert(is_err_frame(decode_ws_frame(e64)), "short ext64")?;
}

test("reject 64-bit length with high octets") {
    let raw: Vec<byte> = Vec::new();
    push_u(raw, 130);
    push_u(raw, 127);
    push_u(raw, 1);
    push_u(raw, 0);
    push_u(raw, 0);
    push_u(raw, 0);
    push_u(raw, 0);
    push_u(raw, 0);
    push_u(raw, 0);
    push_u(raw, 1);
    assert(is_err_frame(decode_ws_frame(raw)), "high 64")?;
}

test("reject payload over 1 MiB") {
    let raw: Vec<byte> = Vec::new();
    push_u(raw, 130);
    push_u(raw, 127);
    push_u(raw, 0);
    push_u(raw, 0);
    push_u(raw, 0);
    push_u(raw, 0);
    push_u(raw, 0);
    push_u(raw, 16);
    push_u(raw, 0);
    push_u(raw, 1);
    assert(is_err_frame(decode_ws_frame(raw)), "over 1MiB")?;
}

test("wire len truncated forms") {
    let empty: Vec<byte> = Vec::new();
    assert(ws_frame_wire_len(empty) == 0, "empty")?;
    let one: Vec<byte> = Vec::new();
    push_u(one, 129);
    assert(ws_frame_wire_len(one) == 0, "one")?;
    let short16: Vec<byte> = Vec::new();
    push_u(short16, 130);
    push_u(short16, 126);
    push_u(short16, 1);
    assert(ws_frame_wire_len(short16) == 0, "ext16 hdr")?;
    let short64: Vec<byte> = Vec::new();
    push_u(short64, 130);
    push_u(short64, 127);
    let i = 0;
    while i < 5 {
        push_u(short64, 0);
        i = i + 1;
    }
    assert(ws_frame_wire_len(short64) == 0, "ext64 hdr")?;
}

test("opcode constants") {
    assert(ws_opcode_cont() == 0, "cont")?;
    assert(ws_opcode_text() == 1, "text")?;
    assert(ws_opcode_bin() == 2, "bin")?;
    assert(ws_opcode_close() == 8, "close")?;
    assert(ws_opcode_ping() == 9, "ping")?;
    assert(ws_opcode_pong() == 10, "pong")?;
}
