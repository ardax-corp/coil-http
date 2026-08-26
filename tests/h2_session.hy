// In-memory HTTP/2 session (preface, SETTINGS ACK, HEADERS/DATA mux).
use string::{to_bytes};
use http::url::{Headers, parse_url};
use http::h2::{
    H2Frame,
    H2Settings,
    connection_preface,
    data_frame,
    decode_frame,
    decode_push_promise_payload,
    encode_frame,
    encode_push_promise_frames,
    empty_settings_frame,
    flag_ack,
    flag_end_headers,
    flag_end_stream,
    frame_type_continuation,
    frame_type_headers,
    frame_type_push_promise,
    frame_type_settings,
    frame_wire_len,
    goaway_frame,
    h2_end_headers_set,
    h2_prior_knowledge_get,
    h2_prior_knowledge_two_gets,
    headers_frame,
    headers_frames,
    headers_from_frame,
    push_promise_frame,
    settings_ack_frame,
    settings_frame,
    settings_id_header_table_size,
    window_update_frame,
};
use http::h2_session::{H2Session};
use http::hpack::{decode_header_block};

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

fn rest_after_frame(Vec<byte> wire) -> Vec<byte> {
    let n = frame_wire_len(wire);
    let out: Vec<byte> = Vec::new();
    let i = n;
    while i < len(wire) {
        out.push(wire[i]);
        i = i + 1;
    }
    return out;
}

test("HEADERS plus CONTINUATION assemble before HPACK") {
    let sess = boot_session();
    let h = Headers::new();
    h.add(":method", "GET");
    h.add(":path", "/continuation-path");
    h.add("x-trace", "www.example.com");
    let wire = headers_frames(1, h, 1, 8);
    let first = match decode_frame(wire) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "first",
    };
    assert(first.typ == frame_type_headers(), "headers")?;
    assert(h2_end_headers_set(first.flags) == 0, "no end headers")?;
    let rest = rest_after_frame(wire);
    let second = match decode_frame(rest) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "cont",
    };
    assert(second.typ == frame_type_continuation(), "continuation")?;
    match sess.feed(wire) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "feed split",
    };
    assert(sess.stream_count() == 1, "one")?;
    let got = match sess.stream_headers(1) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "headers",
    };
    assert(got.count() == 3, "three")?;
    assert(got.value_at(0) == "GET", "GET")?;
    assert(got.value_at(1) == "/continuation-path", "path")?;
    assert(got.value_at(2) == "www.example.com", "host")?;
    let ended = match sess.stream_ended(1) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "ended",
    };
    assert(ended == 1, "end stream on headers")?;
}

test("incomplete HEADERS without CONTINUATION is not a stream yet") {
    let sess = boot_session();
    let h = Headers::new();
    h.add("x-trace", "www.example.com");
    let wire = headers_frames(1, h, 1, 4);
    let first = match decode_frame(wire) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "first",
    };
    match sess.feed(encode_frame(first)) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "partial",
    };
    assert(sess.stream_count() == 0, "waiting")?;
    let rest = rest_after_frame(wire);
    match sess.feed(rest) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "finish",
    };
    assert(sess.stream_count() == 1, "complete")?;
}

test("DATA between HEADERS and CONTINUATION is an error") {
    let sess = boot_session();
    let h = Headers::new();
    h.add("x-trace", "www.example.com");
    let wire = headers_frames(1, h, 0, 4);
    let first = match decode_frame(wire) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "first",
    };
    match sess.feed(encode_frame(first)) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "headers",
    };
    let body = to_bytes("x");
    let r = sess.feed(encode_frame(data_frame(1, body, 1)));
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "data during continuation")?;
}

test("SETTINGS_HEADER_TABLE_SIZE resizes the session table") {
    let sess = boot_session();
    assert(sess.hpack.cap == 4096, "default cap")?;
    assert(sess.hpack.max_size == 4096, "default max")?;
    let st = H2Settings::new();
    st.add(settings_id_header_table_size(), 256);
    match sess.feed(encode_frame(settings_frame(st))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "settings",
    };
    assert(sess.hpack.cap == 256, "cap")?;
    assert(sess.hpack.max_size == 256, "max")?;
}

test("SETTINGS_HEADER_TABLE_SIZE zero evicts dynamic entries") {
    let sess = boot_session();
    let first = hpack_octets(
        130, 134, 132, 65, 15, 119, 119, 119, 46, 101, 120, 97, 109, 112, 108, 101, 46, 99, 111, 109
    );
    match sess.feed(encode_frame(raw_headers(1, first))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "C.3.1",
    };
    let st = H2Settings::new();
    st.add(settings_id_header_table_size(), 0);
    match sess.feed(encode_frame(settings_frame(st))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "resize 0",
    };
    assert(sess.hpack.max_size == 0, "max 0")?;
    assert(sess.hpack.size == 0, "empty")?;
    let second = hpack_octets(130, 134, 132, 190, 88, 8, 110, 111, 45, 99, 97, 99, 104, 101);
    let r = sess.feed(encode_frame(raw_headers(3, second)));
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "idx 62 gone")?;
}

test("PUSH_PROMISE parse stores promised request") {
    let sess = boot_session();
    let h = get_slash_headers();
    match sess.feed(encode_frame(headers_frame(1, h, 1))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "headers",
    };
    let ph = Headers::new();
    ph.add(":method", "GET");
    ph.add(":path", "/style.css");
    ph.add(":authority", "example.com");
    match sess.feed(encode_frame(push_promise_frame(1, 2, ph))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "push",
    };
    assert(sess.push_count() == 1, "one push")?;
    let pid = match sess.push_promised_id(0) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "id",
    };
    assert(pid == 2, "promised 2")?;
    let got = match sess.push_headers(2) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "push headers",
    };
    assert(got.count() == 3, "three")?;
    assert(got.value_at(0) == "GET", "GET")?;
    assert(got.value_at(1) == "/style.css", "path")?;
    assert(got.value_at(2) == "example.com", "auth")?;
}

test("queue_push emits PUSH_PROMISE") {
    let sess = boot_session();
    let h = get_slash_headers();
    match sess.feed(encode_frame(headers_frame(1, h, 1))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "headers",
    };
    sess.queue_push(1, 2, "GET", "/app.js", "example.com");
    let out = sess.drain();
    let f = match decode_frame(out) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode push",
    };
    assert(f.typ == frame_type_push_promise(), "type")?;
    assert(f.stream_id == 1, "associated")?;
    assert(h2_end_headers_set(f.flags) == 1, "end headers")?;
    let p = match decode_push_promise_payload(f.payload) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "payload",
    };
    assert(p.promised_id == 2, "promised")?;
    let decoded = match decode_header_block(p.block) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "hpack",
    };
    assert(decoded.value_at(0) == "GET", "GET")?;
    assert(decoded.value_at(1) == "/app.js", "path")?;
    assert(decoded.value_at(2) == "example.com", "auth")?;
}

test("PUSH_PROMISE then CONTINUATION assembles") {
    let sess = boot_session();
    let h = get_slash_headers();
    match sess.feed(encode_frame(headers_frame(1, h, 1))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "headers",
    };
    let ph = Headers::new();
    ph.add(":method", "GET");
    ph.add(":path", "/pretty-long-pushed-asset.css");
    ph.add(":authority", "www.example.com");
    let wire = encode_push_promise_frames(1, 2, ph, 8);
    let first = match decode_frame(wire) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "pp",
    };
    assert(first.typ == frame_type_push_promise(), "push")?;
    assert(h2_end_headers_set(first.flags) == 0, "no end")?;
    match sess.feed(wire) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "feed pp split",
    };
    assert(sess.push_count() == 1, "one")?;
    let got = match sess.push_headers(2) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "headers",
    };
    assert(got.value_at(1) == "/pretty-long-pushed-asset.css", "path")?;
}

test("odd promised stream id is an error") {
    let sess = boot_session();
    let h = get_slash_headers();
    match sess.feed(encode_frame(headers_frame(1, h, 1))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "headers",
    };
    let ph = Headers::new();
    ph.add(":method", "GET");
    ph.add(":path", "/x");
    let r = sess.feed(encode_frame(push_promise_frame(1, 3, ph)));
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "odd promised")?;
}

test("two GET prior knowledge feeds stream 1 and 3") {
    let u1 = match parse_url("http://example.com/a") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "u1",
    };
    let u2 = match parse_url("http://example.com/b") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "u2",
    };
    let sess = H2Session::new();
    match sess.feed(h2_prior_knowledge_two_gets(u1, u2)) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "feed two",
    };
    assert(sess.stream_count() == 2, "two")?;
    let h1 = match sess.stream_headers(1) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "h1",
    };
    let h3 = match sess.stream_headers(3) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "h3",
    };
    assert(h1.value_at(1) == "/a", "a")?;
    assert(h3.value_at(1) == "/b", "b")?;
}
