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

test("settings ack survives frame wire roundtrip") {
    let f = settings_ack_frame();
    let g = match decode_frame(encode_frame(f)) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "ack wire",
    };
    assert(g.typ == frame_type_settings(), "settings")?;
    assert(g.flags == flag_ack(), "ack flag")?;
    assert(g.stream_id == 0, "stream 0")?;
    assert(len(g.payload) == 0, "empty")?;
}

test("empty settings payload encodes zero bytes") {
    let s = H2Settings::new();
    let raw = encode_settings_payload(s);
    assert(len(raw) == 0, "empty")?;
    let g = match decode_settings_payload(raw) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "empty decode",
    };
    assert(g.count() == 0, "no params")?;
}

test("settings value uses full 32-bit field") {
    let s = H2Settings::new();
    // 16777216 needs the high byte of the 4-byte SETTINGS value.
    s.add(5, 16777216);
    let raw = encode_settings_payload(s);
    assert(len(raw) == 6, "one param")?;
    assert((raw[2] as int) == 1, "value hi")?;
    assert((raw[3] as int) == 0, "mid")?;
    assert((raw[4] as int) == 0, "mid2")?;
    assert((raw[5] as int) == 0, "lo")?;
    let g = match decode_settings_payload(raw) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "big value",
    };
    assert(g.values[0] == 16777216, "max frame size")?;
}

test("window update wrong length is an error") {
    let short: Vec<byte> = Vec::new();
    short.push(0 as byte);
    short.push(0 as byte);
    short.push(0 as byte);
    let r = decode_window_update_payload(short);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "3 bytes")?;
    let long: Vec<byte> = Vec::new();
    long.push(0 as byte);
    long.push(0 as byte);
    long.push(0 as byte);
    long.push(1 as byte);
    long.push(0 as byte);
    let r2 = decode_window_update_payload(long);
    assert(match r2 {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "5 bytes")?;
}

test("window update increment that masks to zero is an error") {
    // 2^31 clears to 0 after the reserved-bit mask (same PROTOCOL_ERROR as increment 0).
    let two31 = 128 * 16777216;
    let e = encode_window_update_payload(two31);
    assert(match e {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "encode 2^31")?;
}

test("window_update_frame rejects zero increment") {
    let r = window_update_frame(1, 0);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "frame zero")?;
}

test("goaway reserved last-stream-id bit is cleared") {
    let raw: Vec<byte> = Vec::new();
    // last-stream-id 0x80000005 → 5; error code 9 (CANCEL)
    raw.push(128 as byte);
    raw.push(0 as byte);
    raw.push(0 as byte);
    raw.push(5 as byte);
    raw.push(0 as byte);
    raw.push(0 as byte);
    raw.push(0 as byte);
    raw.push(9 as byte);
    let g = match decode_goaway_payload(raw) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "goaway reserved",
    };
    assert(g.last_stream_id == 5, "mask bit 31")?;
    assert(g.error_code == 9, "CANCEL")?;
    let mask = 128 * 16777216;
    let encoded = encode_goaway_payload(mask + 5, 9);
    let d = match decode_goaway_payload(encoded) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "encode mask",
    };
    assert(d.last_stream_id == 5, "encode clears bit 31")?;
    assert(d.error_code == 9, "code")?;
}

test("headers frame wire roundtrip keeps HPACK block") {
    let h = Headers::new();
    h.add(":method", "POST");
    h.add(":path", "/");
    let f = headers_frame(7, h, 0);
    let g = match decode_frame(encode_frame(f)) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "headers wire",
    };
    assert(g.typ == frame_type_headers(), "type")?;
    assert(g.stream_id == 7, "sid")?;
    assert(g.flags == flag_end_headers(), "end headers only")?;
    let decoded = match headers_from_frame(g) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "from wire",
    };
    assert(decoded.count() == 2, "two")?;
    assert(decoded.name_at(0) == ":method", "method")?;
    assert(decoded.value_at(0) == "POST", "POST")?;
    assert(decoded.name_at(1) == ":path", "path")?;
    assert(decoded.value_at(1) == "/", "slash")?;
}

test("headers_from_frame propagates bad HPACK payload") {
    // Literal without indexing + Huffman-coded name length (H=1) → Err.
    let lit: Vec<byte> = Vec::new();
    lit.push(0 as byte);
    lit.push(129 as byte);
    let f = H2Frame::new(frame_type_headers(), flag_end_headers(), 1, lit);
    let r = headers_from_frame(f);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "huffman reject")?;
}
