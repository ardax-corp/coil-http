// In-memory HTTP/2 session (preface, SETTINGS ACK, HEADERS/DATA mux).
use string::{to_bytes};
use http::url::{Headers, parse_url};
use http::h2::{
    H2Frame,
    H2Settings,
    connection_preface,
    data_frame,
    decode_frame,
    encode_frame,
    empty_settings_frame,
    flag_ack,
    flag_end_headers,
    flag_end_stream,
    frame_type_headers,
    frame_type_settings,
    goaway_frame,
    h2_prior_knowledge_get,
    headers_frame,
    headers_from_frame,
    settings_ack_frame,
    settings_frame,
    window_update_frame,
};
use http::h2_session::{H2Session};

fn cat_bytes(Vec<byte> a, Vec<byte> b) -> Vec<byte> {
    let out: Vec<byte> = Vec::new();
    let i = 0;
    while i < len(a) {
        out.push(a[i]);
        i = i + 1;
    }
    let j = 0;
    while j < len(b) {
        out.push(b[j]);
        j = j + 1;
    }
    return out;
}

fn get_slash_headers() -> Headers {
    let h = Headers::new();
    h.add(":method", "GET");
    h.add(":path", "/");
    return h;
}

test("preface plus settings yields ack") {
    let s = H2Session::new();
    let wire = cat_bytes(connection_preface(), encode_frame(empty_settings_frame()));
    match s.feed(wire) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "feed",
    };
    let out = s.drain();
    let ack = match decode_frame(out) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "ack decode",
    };
    assert(ack.typ == frame_type_settings(), "settings")?;
    assert(ack.flags == flag_ack(), "ack")?;
    assert(ack.stream_id == 0, "stream 0")?;
    assert(len(ack.payload) == 0, "empty")?;
}

test("bad preface is an error") {
    let s = H2Session::new();
    let r = s.feed(to_bytes("HTTP/1.1"));
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "bad preface")?;
}

test("headers GET slash and data end stream") {
    let sess = H2Session::new();
    let h = get_slash_headers();
    let body = to_bytes("hi");
    let wire = connection_preface();
    wire = cat_bytes(wire, encode_frame(empty_settings_frame()));
    wire = cat_bytes(wire, encode_frame(headers_frame(1, h, 0)));
    wire = cat_bytes(wire, encode_frame(data_frame(1, body, 1)));
    match sess.feed(wire) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "feed",
    };
    assert(sess.stream_count() == 1, "one stream")?;
    let headers = match sess.stream_headers(1) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "headers",
    };
    assert(headers.count() == 2, "two")?;
    assert(headers.name_at(0) == ":method", "method")?;
    assert(headers.value_at(0) == "GET", "GET")?;
    assert(headers.name_at(1) == ":path", "path")?;
    assert(headers.value_at(1) == "/", "slash")?;
    let got = match sess.stream_body(1) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "body",
    };
    assert(len(got) == 2, "len")?;
    assert(got[0] == ("h" as byte), "h")?;
    assert(got[1] == ("i" as byte), "i")?;
    let ended = match sess.stream_ended(1) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "ended",
    };
    assert(ended == 1, "end stream")?;
}

test("two streams interleaved") {
    let sess = H2Session::new();
    let h1 = get_slash_headers();
    let h3 = Headers::new();
    h3.add(":method", "POST");
    h3.add(":path", "/");
    let b1 = to_bytes("ab");
    let b3 = to_bytes("cd");
    let wire = connection_preface();
    wire = cat_bytes(wire, encode_frame(empty_settings_frame()));
    wire = cat_bytes(wire, encode_frame(headers_frame(1, h1, 0)));
    wire = cat_bytes(wire, encode_frame(headers_frame(3, h3, 0)));
    wire = cat_bytes(wire, encode_frame(data_frame(1, b1, 1)));
    wire = cat_bytes(wire, encode_frame(data_frame(3, b3, 1)));
    match sess.feed(wire) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "feed",
    };
    assert(sess.stream_count() == 2, "two streams")?;
    let m1 = match sess.stream_headers(1) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "h1",
    };
    assert(m1.value_at(0) == "GET", "GET")?;
    let m3 = match sess.stream_headers(3) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "h3",
    };
    assert(m3.value_at(0) == "POST", "POST")?;
    let g1 = match sess.stream_body(1) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "b1",
    };
    let g3 = match sess.stream_body(3) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "b3",
    };
    assert(len(g1) == 2, "b1 len")?;
    assert(len(g3) == 2, "b3 len")?;
    assert(g1[0] == ("a" as byte), "a")?;
    assert(g3[0] == ("c" as byte), "c")?;
    let e1 = match sess.stream_ended(1) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "e1",
    };
    let e3 = match sess.stream_ended(3) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "e3",
    };
    assert(e1 == 1, "s1 ended")?;
    assert(e3 == 1, "s3 ended")?;
}

test("headers on stream zero is an error") {
    let sess = H2Session::new();
    let h = get_slash_headers();
    let wire = connection_preface();
    wire = cat_bytes(wire, encode_frame(empty_settings_frame()));
    wire = cat_bytes(wire, encode_frame(headers_frame(0, h, 1)));
    let r = sess.feed(wire);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "stream 0 headers")?;
}

test("data on even stream id is an error") {
    let sess = H2Session::new();
    let h = get_slash_headers();
    let body = to_bytes("x");
    let wire = connection_preface();
    wire = cat_bytes(wire, encode_frame(empty_settings_frame()));
    wire = cat_bytes(wire, encode_frame(headers_frame(1, h, 0)));
    wire = cat_bytes(wire, encode_frame(data_frame(2, body, 1)));
    let r = sess.feed(wire);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "even data")?;
}

test("settings with params still acks") {
    let sess = H2Session::new();
    let st = H2Settings::new();
    st.add(4, 65535);
    let wire = cat_bytes(connection_preface(), encode_frame(settings_frame(st)));
    match sess.feed(wire) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "feed",
    };
    let out = sess.drain();
    let ack = match decode_frame(out) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "ack",
    };
    assert(ack.flags == flag_ack(), "ack")?;
    assert(len(ack.payload) == 0, "empty ack")?;
}

fn boot_session() -> H2Session {
    let sess = H2Session::new();
    let wire = cat_bytes(connection_preface(), encode_frame(empty_settings_frame()));
    match sess.feed(wire) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "boot",
    };
    let _ = sess.drain();
    return sess;
}

test("partial preface then rest completes") {
    let sess = H2Session::new();
    let pref = connection_preface();
    let first: Vec<byte> = Vec::new();
    let i = 0;
    while i < 10 {
        first.push(pref[i]);
        i = i + 1;
    }
    match sess.feed(first) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "partial preface",
    };
    let rest: Vec<byte> = Vec::new();
    while i < 24 {
        rest.push(pref[i]);
        i = i + 1;
    }
    rest = cat_bytes(rest, encode_frame(empty_settings_frame()));
    match sess.feed(rest) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "finish preface",
    };
    let out = sess.drain();
    let ack = match decode_frame(out) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "ack",
    };
    assert(ack.flags == flag_ack(), "ack after split preface")?;
}

test("partial frame waits then completes on next feed") {
    let sess = boot_session();
    let h = get_slash_headers();
    let full = encode_frame(headers_frame(1, h, 1));
    let head: Vec<byte> = Vec::new();
    let i = 0;
    while i < 5 {
        head.push(full[i]);
        i = i + 1;
    }
    match sess.feed(head) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "partial frame",
    };
    assert(sess.stream_count() == 0, "not yet")?;
    let tail: Vec<byte> = Vec::new();
    while i < len(full) {
        tail.push(full[i]);
        i = i + 1;
    }
    match sess.feed(tail) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "finish frame",
    };
    assert(sess.stream_count() == 1, "one stream")?;
    let ended = match sess.stream_ended(1) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "ended",
    };
    assert(ended == 1, "end on headers")?;
}

test("headers before settings is an error") {
    let sess = H2Session::new();
    let h = get_slash_headers();
    let wire = connection_preface();
    wire = cat_bytes(wire, encode_frame(headers_frame(1, h, 1)));
    let r = sess.feed(wire);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "headers before settings")?;
}

test("settings on nonzero stream is an error") {
    let sess = H2Session::new();
    let empty: Vec<byte> = Vec::new();
    let bad = H2Frame::new(frame_type_settings(), 0, 1, empty);
    let wire = cat_bytes(connection_preface(), encode_frame(bad));
    let r = sess.feed(wire);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "settings stream 1")?;
}

test("settings ack does not emit another ack") {
    let sess = H2Session::new();
    let wire = cat_bytes(connection_preface(), encode_frame(settings_ack_frame()));
    match sess.feed(wire) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "feed ack",
    };
    let out = sess.drain();
    assert(len(out) == 0, "no reply ack")?;
    let h = get_slash_headers();
    match sess.feed(encode_frame(headers_frame(1, h, 1))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "headers after ack",
    };
    assert(sess.stream_count() == 1, "stream after client ack")?;
}

test("headers on even stream id is an error") {
    let sess = boot_session();
    let h = get_slash_headers();
    let r = sess.feed(encode_frame(headers_frame(2, h, 1)));
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "even headers")?;
}

test("duplicate headers on same stream is an error") {
    let sess = boot_session();
    let h = get_slash_headers();
    match sess.feed(encode_frame(headers_frame(1, h, 0))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "first headers",
    };
    let r = sess.feed(encode_frame(headers_frame(1, h, 1)));
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "duplicate headers")?;
}

test("data without headers is an error") {
    let sess = boot_session();
    let body = to_bytes("x");
    let r = sess.feed(encode_frame(data_frame(1, body, 1)));
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "orphan data")?;
}

test("data after end stream is an error") {
    let sess = boot_session();
    let h = get_slash_headers();
    let body = to_bytes("a");
    match sess.feed(encode_frame(headers_frame(1, h, 0))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "headers",
    };
    match sess.feed(encode_frame(data_frame(1, body, 1))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "first data",
    };
    let r = sess.feed(encode_frame(data_frame(1, body, 1)));
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "data after end")?;
}

test("two data frames append before end stream") {
    let sess = boot_session();
    let h = get_slash_headers();
    let a = to_bytes("ab");
    let b = to_bytes("cd");
    match sess.feed(encode_frame(headers_frame(1, h, 0))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "headers",
    };
    match sess.feed(encode_frame(data_frame(1, a, 0))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "data1",
    };
    match sess.feed(encode_frame(data_frame(1, b, 1))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "data2",
    };
    let got = match sess.stream_body(1) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "body",
    };
    assert(len(got) == 4, "len")?;
    assert(got[0] == ("a" as byte), "a")?;
    assert(got[2] == ("c" as byte), "c")?;
    let ended = match sess.stream_ended(1) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "ended",
    };
    assert(ended == 1, "ended")?;
}

test("window update and goaway after settings succeed") {
    let sess = boot_session();
    let wu = match window_update_frame(0, 1024) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "wu",
    };
    match sess.feed(encode_frame(wu)) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "window update",
    };
    match sess.feed(encode_frame(goaway_frame(0, 0))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "goaway",
    };
    assert(sess.stream_count() == 0, "no streams")?;
}

test("stream accessors reject unknown id") {
    let sess = boot_session();
    let h = match sess.stream_headers(9) {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    };
    assert(h, "headers")?;
    let b = match sess.stream_body(9) {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    };
    assert(b, "body")?;
    let e = match sess.stream_ended(9) {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    };
    assert(e, "ended")?;
}

test("prior knowledge GET feeds stream 1 headers") {
    let u = match parse_url("http://example.com/") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "url",
    };
    let sess = H2Session::new();
    match sess.feed(h2_prior_knowledge_get(u)) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "feed",
    };
    assert(sess.stream_count() == 1, "one stream")?;
    let headers = match sess.stream_headers(1) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "headers",
    };
    assert(headers.count() == 4, "four")?;
    assert(headers.name_at(0) == ":method", "method")?;
    assert(headers.value_at(0) == "GET", "GET")?;
    assert(headers.name_at(1) == ":path", "path")?;
    assert(headers.value_at(1) == "/", "slash")?;
    assert(headers.name_at(2) == ":scheme", "scheme")?;
    assert(headers.value_at(2) == "http", "http")?;
    assert(headers.name_at(3) == ":authority", "authority")?;
    assert(headers.value_at(3) == "example.com", "host")?;
    let ended = match sess.stream_ended(1) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "ended",
    };
    assert(ended == 1, "end stream")?;
}

test("data on stream zero is an error") {
    let sess = boot_session();
    let h = get_slash_headers();
    match sess.feed(encode_frame(headers_frame(1, h, 0))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "headers",
    };
    let body = to_bytes("x");
    let r = sess.feed(encode_frame(data_frame(0, body, 1)));
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "data stream 0")?;
}

fn hpack_octets(int... xs) -> Vec<byte> {
    let out: Vec<byte> = Vec::new();
    let i = 0;
    while i < len(xs) {
        out.push(xs[i] as byte);
        i = i + 1;
    }
    return out;
}

fn raw_headers(int sid, Vec<byte> payload) -> H2Frame {
    return H2Frame::new(
        frame_type_headers(),
        flag_end_headers() + flag_end_stream(),
        sid,
        payload
    );
}

test("session decoder table persists C.3 dynamic index across HEADERS") {
    // RFC 7541 C.3.1 then C.3.2: second block indexes :authority from the first.
    let sess = boot_session();
    let first = hpack_octets(
        130, 134, 132, 65, 15, 119, 119, 119, 46, 101, 120, 97, 109, 112, 108, 101, 46, 99, 111, 109
    );
    let second = hpack_octets(130, 134, 132, 190, 88, 8, 110, 111, 45, 99, 97, 99, 104, 101);
    match sess.feed(encode_frame(raw_headers(1, first))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "C.3.1 headers",
    };
    match sess.feed(encode_frame(raw_headers(3, second))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "C.3.2 headers",
    };
    assert(sess.stream_count() == 2, "two streams")?;
    let h1 = match sess.stream_headers(1) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "h1",
    };
    assert(h1.count() == 4, "c31 four")?;
    assert(h1.value_at(3) == "www.example.com", "c31 host")?;
    let h3 = match sess.stream_headers(3) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "h3",
    };
    assert(h3.count() == 5, "c32 five")?;
    assert(h3.value_at(0) == "GET", "GET")?;
    assert(h3.name_at(3) == ":authority", "auth")?;
    assert(h3.value_at(3) == "www.example.com", "host from table")?;
    assert(h3.name_at(4) == "cache-control", "cc")?;
    assert(h3.value_at(4) == "no-cache", "no-cache")?;
}

test("fresh headers_from_frame cannot resolve C.3.2 dynamic index") {
    let second = hpack_octets(130, 134, 132, 190, 88, 8, 110, 111, 45, 99, 97, 99, 104, 101);
    let r = headers_from_frame(raw_headers(1, second));
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "idx 62 empty")?;
}
