// RFC 6455 §1.3 / §4 handshake helpers (no sockets).
use string::{to_bytes};
use http::url::{find_bytes, parse_url};
use http::h1::{parse_request};
use http::ws::{
    build_ws_upgrade_request,
    encode_ws_upgrade_response,
    ws_accept_key,
    ws_is_upgrade_req,
    ws_new_key,
};

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
}
