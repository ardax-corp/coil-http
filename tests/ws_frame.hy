// RFC 6455 §5.7 frame encode/decode (no sockets).
use string::{to_bytes};
use http::ws::{
    decode_ws_frame,
    encode_ws_frame,
    ws_frame_wire_len,
    ws_opcode_bin,
    ws_opcode_ping,
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
