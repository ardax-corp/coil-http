// HTTPS ALPN selection helpers and TLS-path request shapes (no live TLS).
use string::{to_bytes};
use http::url::{Url, empty_headers, find_bytes, parse_url};
use http::request::{build_request_head};
use http::h2::{
    connection_preface,
    decode_frame,
    frame_type_headers,
    frame_type_settings,
    h2_alpn_is_h2,
    h2_client_alpn,
    h2_connect,
    h2_get_request_headers,
    h2_prior_knowledge_get,
    headers_from_frame,
};

fn must_url(string s) -> Url {
    let u = match parse_url(s) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "url",
    };
    return u;
}

fn bytes_slice_after(Vec<byte> b, int start) -> Vec<byte> {
    let out: Vec<byte> = Vec::new();
    let i = start;
    while i < len(b) {
        out.push(b[i]);
        i = i + 1;
    }
    return out;
}

test("client alpn offer prefers h2 then http11") {
    assert(h2_client_alpn() == "h2,http/1.1", "offer list")?;
}

test("alpn is h2 only for exact h2 token") {
    assert(h2_alpn_is_h2("h2") == 1, "h2")?;
    assert(h2_alpn_is_h2("http/1.1") == 0, "http11")?;
    assert(h2_alpn_is_h2("") == 0, "empty")?;
    assert(h2_alpn_is_h2("H2") == 0, "case")?;
    assert(h2_alpn_is_h2("h2-14") == 0, "draft")?;
    assert(h2_alpn_is_h2("h2,http/1.1") == 0, "list not selected")?;
}

test("https get headers carry scheme and default authority") {
    let h = h2_get_request_headers(must_url("https://api.example.com/v1"));
    assert(h.count() == 4, "four")?;
    assert(h.value_at(0) == "GET", "GET")?;
    assert(h.value_at(1) == "/v1", "path")?;
    assert(h.value_at(2) == "https", "scheme")?;
    assert(h.value_at(3) == "api.example.com", "authority")?;
}

test("https custom port prior knowledge wire uses https scheme") {
    let u = must_url("https://127.0.0.1:8443/secure");
    let wire = h2_prior_knowledge_get(u);
    let pref = connection_preface();
    let after = bytes_slice_after(wire, len(pref));
    let settings = match decode_frame(after) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "settings",
    };
    assert(settings.typ == frame_type_settings(), "settings")?;
    let settings_len = 9 + len(settings.payload);
    let rest = bytes_slice_after(after, settings_len);
    let headers = match decode_frame(rest) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "headers",
    };
    assert(headers.typ == frame_type_headers(), "headers type")?;
    assert(headers.stream_id == 1, "stream 1")?;
    let decoded = match headers_from_frame(headers) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode",
    };
    assert(decoded.value_at(1) == "/secure", "path")?;
    assert(decoded.value_at(2) == "https", "scheme")?;
    assert(decoded.value_at(3) == "127.0.0.1:8443", "authority")?;
}

test("http11 fallback request head for https url") {
    let u = must_url("https://example.com:8443/fb");
    let hs = empty_headers();
    let msg = match build_request_head("GET", u, hs, 0) {
        Result::Ok(m) => m,
        Result::Err(_) => panic "build",
    };
    let getb = to_bytes("GET /fb HTTP/1.1");
    let hostb = to_bytes("Host: example.com:8443");
    let closeb = to_bytes("Connection: close");
    if find_bytes(msg, getb) == 999999 { panic "request line"; }
    if find_bytes(msg, hostb) == 999999 { panic "host with port"; }
    if find_bytes(msg, closeb) == 999999 { panic "connection close"; }
}

test("h2_connect cleartext refused port is err") {
    let c = h2_connect("http://127.0.0.1:1/");
    assert(match c {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "connect http refused")?;
}
