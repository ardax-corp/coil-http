// HTTP/2 frame header encode/decode (no sockets).
use string::{to_bytes};
use http::h2::{
    H2Frame,
    connection_preface,
    decode_frame,
    empty_settings_frame,
    encode_frame,
    frame_type_data,
    frame_type_ping,
    frame_type_settings,
    preface_ok,
};

test("settings frame roundtrip") {
    let f = empty_settings_frame();
    let wire = encode_frame(f);
    assert(len(wire) == 9, "header only")?;
    let g = match decode_frame(wire) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode",
    };
    assert(g.typ == frame_type_settings(), "type")?;
    assert(g.stream_id == 0, "stream 0")?;
    assert(len(g.payload) == 0, "empty")?;
}

test("data frame payload") {
    let body = to_bytes("hi");
    let f = H2Frame::new(frame_type_data(), 1, 1, body);
    let wire = encode_frame(f);
    let g = match decode_frame(wire) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode",
    };
    assert(g.typ == frame_type_data(), "data")?;
    assert(g.flags == 1, "end stream")?;
    assert(g.stream_id == 1, "sid")?;
    assert(len(g.payload) == 2, "len")?;
}

test("truncated frame is an error") {
    let raw = to_bytes("short");
    let r = decode_frame(raw);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "truncated")?;
}

test("connection preface") {
    let p = connection_preface();
    assert(preface_ok(p) == 1, "self")?;
    assert(len(p) == 24, "24 bytes")?;
    assert(preface_ok(to_bytes("HTTP/1.1")) == 0, "not h1")?;
}

test("ping frame 8-byte payload") {
    let payload: Vec<byte> = Vec::new();
    let i = 0;
    while i < 8 {
        payload.push(i as byte);
        i = i + 1;
    }
    let f = H2Frame::new(frame_type_ping(), 0, 0, payload);
    let g = match decode_frame(encode_frame(f)) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode",
    };
    assert(g.typ == frame_type_ping(), "ping")?;
    assert(len(g.payload) == 8, "opaque")?;
}
