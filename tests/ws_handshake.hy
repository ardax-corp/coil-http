// RFC 6455 §1.3 / §4 handshake helpers (no sockets).
use string::{to_bytes};
use http::url::{find_bytes, parse_url};
use http::h1::{IncomingRequest, parse_request};
use http::response::{parse_response};
use http::ws::{
    build_ws_upgrade_request,
    encode_ws_upgrade_response,
    ws_accept_key,
    ws_check_upgrade_resp,
    ws_is_upgrade_req,
    ws_new_key,
};

fn must_req(string s) -> IncomingRequest {
    let r = match parse_request(to_bytes(s)) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "parse req",
    };
    return r;
}

test("rfc 6455 accept key") {
    let accept = ws_accept_key("dGhlIHNhbXBsZSBub25jZQ==");
    assert(accept == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", "accept")?;
}

test("upgrade request wire") {
    let u = match parse_url("ws://example.com/chat") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "url",
    };
    let raw = build_ws_upgrade_request(u, "dGhlIHNhbXBsZSBub25jZQ==");
    let req = match parse_request(raw) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "parse",
    };
    assert(req.method_val() == "GET", "method")?;
    assert(req.path_val() == "/chat", "path")?;
    assert(ws_is_upgrade_req(req) == 1, "upgrade")?;
}

test("upgrade response has 101 and accept") {
    let wire = encode_ws_upgrade_response("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=");
    if find_bytes(wire, to_bytes("HTTP/1.1 101")) == 999999 { panic "status"; }
    if find_bytes(wire, to_bytes("Upgrade: websocket")) == 999999 { panic "upgrade"; }
    if find_bytes(wire, to_bytes("Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")) == 999999 { panic "accept"; }
}

test("ws url defaults") {
    let u = match parse_url("ws://example.com/socket") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "ws",
    };
    assert(u.scheme == "ws", "scheme")?;
    assert(u.port == 80, "port")?;
    let s = match parse_url("wss://example.com/socket") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "wss",
    };
    assert(s.scheme == "wss", "wss")?;
    assert(s.port == 443, "443")?;
}

test("key is 24-char base64") {
    let k = ws_new_key(42);
    assert(len(to_bytes(k)) == 24, "b64 16 bytes")?;
    let k2 = ws_new_key(43);
    assert(len(to_bytes(k2)) == 24, "other seed")?;
}

test("second accept key vector") {
    let accept = ws_accept_key("x3JJHMbDL1EzLkh9GBhXDw==");
    assert(accept == "HSmrc0sMlYUkAGmm5OPpG2HaGWk=", "accept 2")?;
}

test("upgrade request host includes non-default port") {
    let u = match parse_url("ws://example.com:9000/chat?x=1") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "url",
    };
    let raw = build_ws_upgrade_request(u, "dGhlIHNhbXBsZSBub25jZQ==");
    if find_bytes(raw, to_bytes("GET /chat?x=1 HTTP/1.1")) == 999999 { panic "path"; }
    if find_bytes(raw, to_bytes("Host: example.com:9000")) == 999999 { panic "host port"; }
    if find_bytes(raw, to_bytes("Sec-WebSocket-Version: 13")) == 999999 { panic "version"; }
}

test("wss default host omits 443") {
    let u = match parse_url("wss://example.com/socket") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "url",
    };
    let raw = build_ws_upgrade_request(u, "dGhlIHNhbXBsZSBub25jZQ==");
    if find_bytes(raw, to_bytes("Host: example.com\r\n")) == 999999 { panic "host"; }
}

test("upgrade headers are case insensitive") {
    let req = must_req("GET / HTTP/1.1\r\nUpgrade: WebSocket\r\nConnection: keep-alive, Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n");
    assert(ws_is_upgrade_req(req) == 1, "ci upgrade")?;
}

test("reject post upgrade") {
    let req = must_req("POST / HTTP/1.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n");
    assert(ws_is_upgrade_req(req) == 0, "post")?;
}

test("reject missing upgrade header") {
    let req = must_req("GET / HTTP/1.1\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n");
    assert(ws_is_upgrade_req(req) == 0, "no upgrade")?;
}

test("reject missing connection upgrade") {
    let req = must_req("GET / HTTP/1.1\r\nUpgrade: websocket\r\nConnection: keep-alive\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n");
    assert(ws_is_upgrade_req(req) == 0, "no conn")?;
}

test("reject wrong version") {
    let req = must_req("GET / HTTP/1.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 8\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n");
    assert(ws_is_upgrade_req(req) == 0, "v8")?;
}

test("reject missing key") {
    let req = must_req("GET / HTTP/1.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\n\r\n");
    assert(ws_is_upgrade_req(req) == 0, "no key")?;
}

test("check upgrade resp rfc accept") {
    let key = "dGhlIHNhbXBsZSBub25jZQ==";
    let wire = encode_ws_upgrade_response(ws_accept_key(key));
    let resp = match parse_response(wire) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "parse 101",
    };
    match ws_check_upgrade_resp(resp, key) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "accept ok",
    };
}

test("reject upgrade resp not 101") {
    let raw = to_bytes("HTTP/1.1 200 OK\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n\r\n");
    let resp = match parse_response(raw) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "parse 200",
    };
    let r = ws_check_upgrade_resp(resp, "dGhlIHNhbXBsZSBub25jZQ==");
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "not 101")?;
}

test("reject upgrade resp wrong accept") {
    let wire = encode_ws_upgrade_response("AAAAAAAAAAAAAAAAAAAAAAAAAAA=");
    let resp = match parse_response(wire) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "parse accept",
    };
    let r = ws_check_upgrade_resp(resp, "dGhlIHNhbXBsZSBub25jZQ==");
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "bad accept")?;
}

test("reject upgrade resp missing upgrade header") {
    let raw = to_bytes("HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n\r\n");
    let resp = match parse_response(raw) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "parse missing",
    };
    let r = ws_check_upgrade_resp(resp, "dGhlIHNhbXBsZSBub25jZQ==");
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "no upgrade")?;
}
