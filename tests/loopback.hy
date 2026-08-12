// H1 request/response roundtrip (no sockets; full loopback in examples/loopback.hy).
use string::{to_bytes};
use http::url::{find_bytes};
use http::h1::{parse_request, encode_response};
use http::response::Response;

test("parse request and build response") {
    let raw = to_bytes("GET /hello HTTP/1.1\r\nHost: example.com\r\nContent-Length: 0\r\n\r\n");
    let req = match parse_request(raw) {
        Result::Ok(r) => r,
        Result::Err(_) => panic "parse request",
    };
    assert(req.method_val() == "GET", "method")?;
    assert(req.path_val() == "/hello", "path")?;
    let resp = Response::ok();
    resp.header("Content-Type", "text/plain");
    resp.body(to_bytes("ok"));
    let wire = encode_response(resp);
    let okb = to_bytes("200");
    let bodyb = to_bytes("ok");
    if find_bytes(wire, okb) == 999999 { panic "status in wire"; }
    if find_bytes(wire, bodyb) == 999999 { panic "body in wire"; }
}
