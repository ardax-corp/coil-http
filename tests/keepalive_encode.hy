// Keep-alive response encode and Connection: close detection (no sockets).
use string::{to_bytes};
use http::url::{find_bytes};
use http::h1::{
    encode_response,
    encode_response_keepalive,
    incoming_wants_close,
    parse_request,
};
use http::response::{Response};

test("encode_response_keepalive sets keep-alive not close") {
    let r = Response::ok();
    r.body(to_bytes("hi"));
    let wire = encode_response_keepalive(r);
    let keep = to_bytes("Connection: keep-alive");
    let close = to_bytes("Connection: close");
    let cl = to_bytes("Content-Length: 2");
    if find_bytes(wire, keep) == 999999 { panic "keep-alive"; }
    if find_bytes(wire, close) != 999999 { panic "must not close"; }
    if find_bytes(wire, cl) == 999999 { panic "content-length"; }
}

test("encode_response defaults to connection close") {
    let r = Response::ok();
    r.body(to_bytes("hi"));
    let wire = encode_response(r);
    let close = to_bytes("Connection: close");
    let keep = to_bytes("Connection: keep-alive");
    if find_bytes(wire, close) == 999999 { panic "close"; }
    if find_bytes(wire, keep) != 999999 { panic "must not keep-alive"; }
}

test("encode_response_keepalive chunked omits content-length") {
    let r = Response::ok();
    r.header("Transfer-Encoding", "chunked");
    r.body(to_bytes("ok"));
    let wire = encode_response_keepalive(r);
    let te = to_bytes("Transfer-Encoding: chunked");
    let keep = to_bytes("Connection: keep-alive");
    let cl = to_bytes("Content-Length:");
    if find_bytes(wire, te) == 999999 { panic "te"; }
    if find_bytes(wire, keep) == 999999 { panic "keep-alive"; }
    if find_bytes(wire, cl) != 999999 { panic "no content-length"; }
}

test("incoming_wants_close detects Connection close") {
    let raw = to_bytes("GET / HTTP/1.1\r\nHost: h\r\nConnection: close\r\n\r\n");
    let req = match parse_request(raw) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "parse",
    };
    assert(incoming_wants_close(req) == 1, "wants close")?;
}

test("incoming_wants_close is false without Connection close") {
    let raw = to_bytes("GET / HTTP/1.1\r\nHost: h\r\n\r\n");
    let req = match parse_request(raw) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "parse",
    };
    assert(incoming_wants_close(req) == 0, "keep open")?;
}

test("incoming_wants_close is case-insensitive on Close") {
    let raw = to_bytes("GET / HTTP/1.1\r\nHost: h\r\nConnection: Close\r\n\r\n");
    let req = match parse_request(raw) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "parse",
    };
    assert(incoming_wants_close(req) == 1, "Close")?;
}
