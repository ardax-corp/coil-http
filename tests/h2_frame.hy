// HTTP/2 frame header encode/decode (no sockets).
use string::{to_bytes};
use http::h2::{
    H2Frame,
    connection_preface,
    data_frame,
    decode_frame,
    empty_settings_frame,
    encode_frame,
    frame_type_data,
    frame_type_goaway,
    frame_type_headers,
    frame_type_ping,
    frame_type_push_promise,
    frame_type_settings,
    frame_type_window_update,
    frame_type_continuation,
    frame_wire_len,
    h2_connect,
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

test("incomplete payload after valid header is an error") {
    // Length field claims 4 bytes; only 2 follow the 9-byte header.
    let raw: Vec<byte> = Vec::new();
    raw.push(0 as byte);
    raw.push(0 as byte);
    raw.push(4 as byte);
    raw.push(frame_type_data() as byte);
    raw.push(0 as byte);
    raw.push(0 as byte);
    raw.push(0 as byte);
    raw.push(0 as byte);
    raw.push(1 as byte);
    raw.push(("a" as byte));
    raw.push(("b" as byte));
    let r = decode_frame(raw);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "short payload")?;
}

test("decode ignores trailing bytes after first frame") {
    let f = empty_settings_frame();
    let wire = encode_frame(f);
    wire.push(("X" as byte));
    wire.push(("Y" as byte));
    let g = match decode_frame(wire) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode with trailer",
    };
    assert(g.typ == frame_type_settings(), "settings")?;
    assert(len(g.payload) == 0, "empty payload")?;
}

test("reserved stream id bit is cleared on decode") {
    // Wire stream id with bit 31 set (0x80000001) must yield stream 1.
    let raw: Vec<byte> = Vec::new();
    raw.push(0 as byte);
    raw.push(0 as byte);
    raw.push(0 as byte);
    raw.push(frame_type_settings() as byte);
    raw.push(0 as byte);
    raw.push(128 as byte);
    raw.push(0 as byte);
    raw.push(0 as byte);
    raw.push(1 as byte);
    let g = match decode_frame(raw) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode reserved",
    };
    assert(g.stream_id == 1, "mask reserved bit")?;
}

test("multi-byte stream id and length roundtrip") {
    let payload: Vec<byte> = Vec::new();
    let i = 0;
    let mod256 = 128 + 128;
    while i < 300 {
        payload.push((i % mod256) as byte);
        i = i + 1;
    }
    let sid = 65537;
    let f = H2Frame::new(frame_type_headers(), 4, sid, payload);
    let wire = encode_frame(f);
    assert(len(wire) == 9 + 300, "wire len")?;
    assert(wire[0] == (0 as byte), "len hi")?;
    assert(wire[1] == (1 as byte), "len mid 256")?;
    assert(wire[2] == (44 as byte), "len lo 44")?;
    let g = match decode_frame(wire) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode large",
    };
    assert(g.typ == frame_type_headers(), "headers")?;
    assert(g.flags == 4, "end headers")?;
    assert(g.stream_id == sid, "sid")?;
    assert(len(g.payload) == 300, "payload len")?;
    assert(g.payload[0] == (0 as byte), "first")?;
    assert(g.payload[299] == (43 as byte), "last")?;
}

test("preface accepts longer buffer and rejects truncated") {
    let p = connection_preface();
    p.push(("Z" as byte));
    assert(preface_ok(p) == 1, "prefix + junk")?;
    let short = to_bytes("PRI * HTTP/2.0\r\n\r\nSM\r\n\r");
    assert(preface_ok(short) == 0, "truncated")?;
}

test("h2_connect https refused port is err") {
    let c = h2_connect("https://127.0.0.1:1/");
    assert(match c {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "connect https refused")?;
}

test("goaway and window_update encode type bytes") {
    let empty: Vec<byte> = Vec::new();
    let g = match decode_frame(encode_frame(H2Frame::new(frame_type_goaway(), 0, 0, empty))) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "goaway",
    };
    assert(g.typ == 7, "goaway type")?;
    let empty2: Vec<byte> = Vec::new();
    let w = match decode_frame(encode_frame(H2Frame::new(frame_type_window_update(), 0, 0, empty2))) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "window",
    };
    assert(w.typ == 8, "window_update type")?;
}

test("frame_wire_len short and complete") {
    let empty: Vec<byte> = Vec::new();
    assert(frame_wire_len(empty) == 0, "empty")?;
    let short = to_bytes("12345678");
    assert(frame_wire_len(short) == 0, "lt 9")?;
    let wire = encode_frame(empty_settings_frame());
    assert(frame_wire_len(wire) == 9, "settings")?;
    let cut: Vec<byte> = Vec::new();
    let i = 0;
    while i < 8 {
        cut.push(wire[i]);
        i = i + 1;
    }
    assert(frame_wire_len(cut) == 0, "truncated header")?;
    let body = to_bytes("hi");
    let data = encode_frame(data_frame(1, body, 0));
    assert(frame_wire_len(data) == 11, "9+2")?;
    let half: Vec<byte> = Vec::new();
    let j = 0;
    while j < 10 {
        half.push(data[j]);
        j = j + 1;
    }
    assert(frame_wire_len(half) == 0, "truncated payload")?;
}

test("data_frame end stream flag") {
    let body = to_bytes("xy");
    let open = data_frame(3, body, 0);
    assert(open.typ == frame_type_data(), "type")?;
    assert(open.flags == 0, "open")?;
    assert(open.stream_id == 3, "sid")?;
    assert(len(open.payload) == 2, "len")?;
    let ended = data_frame(3, body, 1);
    assert(ended.flags == 1, "end stream")?;
}

test("continuation and push_promise type ids") {
    assert(frame_type_push_promise() == 5, "push")?;
    assert(frame_type_continuation() == 9, "cont")?;
}
