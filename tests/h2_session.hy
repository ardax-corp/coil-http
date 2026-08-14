// In-memory HTTP/2 session (preface, SETTINGS ACK, HEADERS/DATA mux).
use string::{to_bytes};
use http::url::{Headers};
use http::h2::{
    H2Settings,
    connection_preface,
    data_frame,
    decode_frame,
    encode_frame,
    empty_settings_frame,
    flag_ack,
    frame_type_settings,
    headers_frame,
    settings_frame,
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
