// Framed Content-Length: first message end in a buffer (no sockets).
use string::{to_bytes};
use http::response::{http_framed_end, parse_response};
use http::h1::{parse_request};

test("framed end of response with content-length") {
    let raw = to_bytes("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nokEXTRA");
    let end = match http_framed_end(raw) {
        Result::Ok(n) => n,
        Result::Err(_) => panic "framed end",
    };
    let extra = to_bytes("EXTRA");
    assert(end + len(extra) == len(raw), "end before EXTRA")?;
    let first: Vec<byte> = Vec::new();
    let i = 0;
    while i < end {
        first.push(raw[i]);
        i = i + 1;
    }
    let r = match parse_response(first) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "parse first",
    };
    assert(r.status == 200, "status")?;
    assert(len(r.body) == 2, "body")?;
}

test("two concatenated responses keep only the first") {
    let raw = to_bytes("HTTP/1.1 200 OK\r\nContent-Length: 1\r\n\r\nAHTTP/1.1 200 OK\r\nContent-Length: 1\r\n\r\nB");
    let end = match http_framed_end(raw) {
        Result::Ok(n) => n,
        Result::Err(_) => panic "framed end",
    };
    let first: Vec<byte> = Vec::new();
    let i = 0;
    while i < end {
        first.push(raw[i]);
        i = i + 1;
    }
    let r = match parse_response(first) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "parse",
    };
    assert(len(r.body) == 1, "first body")?;
    assert(r.body[0] == ("A" as byte), "body A")?;
}

test("missing content-length ends at header terminator") {
    let raw = to_bytes("HTTP/1.1 204 No Content\r\n\r\nNEXT");
    let end = match http_framed_end(raw) {
        Result::Ok(n) => n,
        Result::Err(_) => panic "framed end",
    };
    let extra = to_bytes("NEXT");
    assert(end + len(extra) == len(raw), "header only")?;
}

test("truncated body is an error") {
    let raw = to_bytes("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nok");
    let r = http_framed_end(raw);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "expected truncated Err")?;
}

test("framed request with extra pipelined bytes") {
    let raw = to_bytes("POST /x HTTP/1.1\r\nHost: h\r\nContent-Length: 3\r\n\r\nabcGET / HTTP/1.1\r\n\r\n");
    let end = match http_framed_end(raw) {
        Result::Ok(n) => n,
        Result::Err(_) => panic "framed end",
    };
    let first: Vec<byte> = Vec::new();
    let i = 0;
    while i < end {
        first.push(raw[i]);
        i = i + 1;
    }
    let req = match parse_request(first) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "parse request",
    };
    assert(req.method_val() == "POST", "method")?;
    assert(len(req.body_val()) == 3, "body len")?;
}

test("chunked transfer-encoding frames through last chunk") {
    let raw = to_bytes("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\nXXXX");
    let end = match http_framed_end(raw) {
        Result::Ok(n) => n,
        Result::Err(_) => panic "framed end",
    };
    let extra = to_bytes("XXXX");
    assert(end + len(extra) == len(raw), "end before XXXX")?;
}
