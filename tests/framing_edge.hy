// Framing helpers: body-len sentinels, trailers, reject bad chunk wire (no sockets).
use string::{to_bytes};
use http::h1::{decode_chunked_body, encode_chunked_body};
use http::response::{header_block_body_len, http_framed_end, parse_response};

test("header_block_body_len content-length") {
    let h = to_bytes("HTTP/1.1 200 OK\r\nContent-Length: 4");
    let n = match header_block_body_len(h) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "body len",
    };
    assert(n == 4, "cl 4")?;
}

test("header_block_body_len missing is empty-body sentinel") {
    let h = to_bytes("HTTP/1.1 204 No Content\r\n");
    let n = match header_block_body_len(h) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "body len",
    };
    assert(n == 999999, "no cl")?;
}

test("header_block_body_len chunked is chunked sentinel") {
    let h = to_bytes("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked");
    let n = match header_block_body_len(h) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "body len",
    };
    assert(n == 999998, "chunked")?;
}

test("header_block_body_len prefers transfer-encoding over content-length") {
    let h = to_bytes("HTTP/1.1 200 OK\r\nContent-Length: 99\r\nTransfer-Encoding: chunked");
    let n = match header_block_body_len(h) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "body len",
    };
    assert(n == 999998, "te wins")?;
}

test("decode chunked with trailer headers") {
    let raw = to_bytes("5\r\nhello\r\n0\r\nX-Trail: 1\r\n\r\n");
    let out = match decode_chunked_body(raw) {
        Result::Ok(b) => b,
        Result::Err(_) => panic "decode",
    };
    assert(len(out) == 5, "body ignores trailers")?;
    assert(out[0] == ("h" as byte), "h")?;
}

test("framed end includes trailers before pipelined bytes") {
    let raw = to_bytes("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\nX-Trail: 1\r\n\r\nNEXT");
    let end = match http_framed_end(raw) {
        Result::Ok(n) => n,
        Result::Err(_) => panic "framed end",
    };
    let extra = to_bytes("NEXT");
    assert(end + len(extra) == len(raw), "end before NEXT")?;
}

test("reject non-hex chunk size") {
    let raw = to_bytes("Z\r\nhello\r\n0\r\n\r\n");
    let r = decode_chunked_body(raw);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "bad size")?;
}

test("reject missing crlf after chunk data") {
    let raw = to_bytes("5\r\nhelloXX0\r\n\r\n");
    let r = decode_chunked_body(raw);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "bad terminator")?;
}

test("parse response prefers chunked over content-length") {
    let raw = to_bytes("HTTP/1.1 200 OK\r\nContent-Length: 99\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n");
    let r = match parse_response(raw) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "parse",
    };
    assert(len(r.body) == 5, "chunked body")?;
}

test("encode empty body as zero chunk only") {
    let empty: Vec<byte> = Vec::new();
    let wire = match encode_chunked_body(empty) {
        Result::Ok(b) => b,
        Result::Err(_) => panic "encode",
    };
    let out = match decode_chunked_body(wire) {
        Result::Ok(b) => b,
        Result::Err(_) => panic "decode",
    };
    assert(len(out) == 0, "empty")?;
}
