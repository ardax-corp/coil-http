// Chunked transfer-encoding encode/decode (no sockets).
use string::{to_bytes};
use http::url::{find_bytes};
use http::h1::{decode_chunked_body, encode_chunked_body, parse_request, encode_response};
use http::response::{http_framed_end, parse_response, Response};

test("encode then decode roundtrip") {
    let src = to_bytes("hello");
    let wire = match encode_chunked_body(src) {
        Result::Ok(b) => b,
        Result::Err(_) => panic "encode",
    };
    let out = match decode_chunked_body(wire) {
        Result::Ok(b) => b,
        Result::Err(_) => panic "decode",
    };
    assert(len(out) == 5, "len")?;
    assert(out[0] == ("h" as byte), "h")?;
}

test("decode two chunks") {
    let raw = to_bytes("5\r\nhello\r\n1\r\n!\r\n0\r\n\r\n");
    let out = match decode_chunked_body(raw) {
        Result::Ok(b) => b,
        Result::Err(_) => panic "decode",
    };
    assert(len(out) == 6, "len")?;
    assert(out[5] == ("!" as byte), "bang")?;
}

test("decode ignores chunk extensions") {
    let raw = to_bytes("5;ext=1\r\nhello\r\n0\r\n\r\n");
    let out = match decode_chunked_body(raw) {
        Result::Ok(b) => b,
        Result::Err(_) => panic "decode",
    };
    assert(len(out) == 5, "len")?;
}

test("reject truncated chunk") {
    let raw = to_bytes("5\r\nhel");
    let r = decode_chunked_body(raw);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "truncated")?;
}

test("parse chunked response") {
    let raw = to_bytes("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n");
    let r = match parse_response(raw) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "parse",
    };
    assert(r.status == 200, "status")?;
    assert(len(r.body) == 5, "body")?;
}

test("parse chunked request") {
    let raw = to_bytes("POST /x HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n0\r\n\r\n");
    let req = match parse_request(raw) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "parse",
    };
    assert(req.method_val() == "POST", "method")?;
    assert(len(req.body_val()) == 3, "body")?;
}

test("framed end of chunked response with extra bytes") {
    let raw = to_bytes("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\nNEXT");
    let end = match http_framed_end(raw) {
        Result::Ok(n) => n,
        Result::Err(_) => panic "framed end",
    };
    let extra = to_bytes("NEXT");
    assert(end + len(extra) == len(raw), "end before NEXT")?;
}

test("encode_response uses chunked when header set") {
    let r = Response::ok();
    r.header("Transfer-Encoding", "chunked");
    r.body(to_bytes("ok"));
    let wire = encode_response(r);
    let te = to_bytes("Transfer-Encoding: chunked");
    let cl = to_bytes("Content-Length:");
    if find_bytes(wire, te) == 999999 { panic "te"; }
    if find_bytes(wire, cl) != 999999 { panic "no content-length"; }
}
