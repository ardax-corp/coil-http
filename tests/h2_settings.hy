// HTTP/2 SETTINGS, WINDOW_UPDATE, GOAWAY payloads and HEADERS+HPACK.
use http::url::{Headers};
use http::h2::{
    H2Frame,
    H2Settings,
    decode_frame,
    decode_goaway_payload,
    decode_settings_payload,
    decode_window_update_payload,
    encode_frame,
    encode_goaway_payload,
    encode_settings_payload,
    encode_window_update_payload,
    flag_ack,
    flag_end_headers,
    flag_end_stream,
    frame_type_headers,
    frame_type_settings,
    goaway_frame,
    headers_frame,
    headers_from_frame,
    settings_ack_frame,
    settings_frame,
    window_update_frame,
};

test("settings payload roundtrip") {
    let s = H2Settings::new();
    s.add(4, 65535);
    s.add(3, 100);
    let raw = encode_settings_payload(s);
    assert(len(raw) == 12, "two params")?;
    let g = match decode_settings_payload(raw) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode settings",
    };
    assert(g.count() == 2, "count")?;
    assert(g.ids[0] == 4, "id 4")?;
    assert(g.values[0] == 65535, "init window")?;
    assert(g.ids[1] == 3, "id 3")?;
    assert(g.values[1] == 100, "max concurrent")?;
}

test("settings frame wraps payload") {
    let s = H2Settings::new();
    s.add(1, 4096);
    let f = settings_frame(s);
    let g = match decode_frame(encode_frame(f)) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode frame",
    };
    assert(g.typ == frame_type_settings(), "type")?;
    assert(g.stream_id == 0, "stream 0")?;
    assert(len(g.payload) == 6, "one param")?;
    let p = match decode_settings_payload(g.payload) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "payload",
    };
    assert(p.ids[0] == 1, "header table")?;
    assert(p.values[0] == 4096, "4096")?;
}

test("settings ack has empty payload") {
    let f = settings_ack_frame();
    assert(f.flags == flag_ack(), "ack")?;
    assert(len(f.payload) == 0, "empty")?;
    let g = match decode_settings_payload(f.payload) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "ack decode",
    };
    assert(g.count() == 0, "no params")?;
}

test("settings payload length not multiple of 6 is an error") {
    let raw: Vec<byte> = Vec::new();
    raw.push(0 as byte);
    raw.push(1 as byte);
    raw.push(0 as byte);
    raw.push(0 as byte);
    let r = decode_settings_payload(raw);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "bad length")?;
}

test("window update payload roundtrip") {
    let raw = match encode_window_update_payload(1024) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "encode wu",
    };
    assert(len(raw) == 4, "4 bytes")?;
    let inc = match decode_window_update_payload(raw) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode wu",
    };
    assert(inc == 1024, "1024")?;
}

test("window update zero increment is an error") {
    let e = encode_window_update_payload(0);
    assert(match e {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "encode zero")?;
    let raw: Vec<byte> = Vec::new();
    raw.push(0 as byte);
    raw.push(0 as byte);
    raw.push(0 as byte);
    raw.push(0 as byte);
    let d = decode_window_update_payload(raw);
    assert(match d {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "decode zero")?;
}

test("window update reserved bit is cleared") {
    let raw: Vec<byte> = Vec::new();
    raw.push(128 as byte);
    raw.push(0 as byte);
    raw.push(0 as byte);
    raw.push(16 as byte);
    let inc = match decode_window_update_payload(raw) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "reserved",
    };
    assert(inc == 16, "mask bit 31")?;
}

test("window update frame roundtrip") {
    let f = match window_update_frame(3, 256) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "wu frame",
    };
    let g = match decode_frame(encode_frame(f)) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode",
    };
    assert(g.typ == 8, "type")?;
    assert(g.stream_id == 3, "sid")?;
    let inc = match decode_window_update_payload(g.payload) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "inc",
    };
    assert(inc == 256, "256")?;
}

test("goaway last stream and error code") {
    let raw = encode_goaway_payload(7, 1);
    assert(len(raw) == 8, "8 bytes")?;
    let g = match decode_goaway_payload(raw) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "goaway",
    };
    assert(g.last_stream_id == 7, "last")?;
    assert(g.error_code == 1, "PROTOCOL_ERROR")?;
}

test("goaway frame and extra debug data") {
    let f = goaway_frame(5, 2);
    let g = match decode_frame(encode_frame(f)) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "frame",
    };
    assert(g.typ == 7, "goaway")?;
    let p = match decode_goaway_payload(g.payload) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "payload",
    };
    assert(p.last_stream_id == 5, "last")?;
    assert(p.error_code == 2, "INTERNAL_ERROR")?;
    g.payload.push(("x" as byte));
    let d = match decode_goaway_payload(g.payload) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "debug",
    };
    assert(d.last_stream_id == 5, "still last")?;
    assert(d.error_code == 2, "still code")?;
}

test("goaway short payload is an error") {
    let raw: Vec<byte> = Vec::new();
    raw.push(0 as byte);
    raw.push(0 as byte);
    raw.push(0 as byte);
    raw.push(1 as byte);
    let r = decode_goaway_payload(raw);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "short")?;
}

test("headers frame GET path slash via HPACK") {
    let h = Headers::new();
    h.add(":method", "GET");
    h.add(":path", "/");
    let f = headers_frame(1, h, 1);
    assert(f.typ == frame_type_headers(), "headers")?;
    assert(f.stream_id == 1, "sid")?;
    assert(f.flags == flag_end_headers() + flag_end_stream(), "flags")?;
    assert(len(f.payload) == 2, "two indexed")?;
    assert((f.payload[0] as int) == 130, "index 2")?;
    assert((f.payload[1] as int) == 132, "index 4")?;
    let g = match headers_from_frame(f) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "from frame",
    };
    assert(g.count() == 2, "two")?;
    assert(g.name_at(0) == ":method", "method")?;
    assert(g.value_at(0) == "GET", "GET")?;
    assert(g.name_at(1) == ":path", "path")?;
    assert(g.value_at(1) == "/", "slash")?;
}

test("headers frame without end stream") {
    let h = Headers::new();
    h.add(":method", "GET");
    let f = headers_frame(1, h, 0);
    assert(f.flags == flag_end_headers(), "end headers only")?;
}

test("headers_from_frame rejects other types") {
    let empty: Vec<byte> = Vec::new();
    let f = H2Frame::new(frame_type_settings(), 0, 0, empty);
    let r = headers_from_frame(f);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "not headers")?;
}
