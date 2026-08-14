// Cleartext prior-knowledge helpers (authority, status, request wire).
use http::url::{Headers, Url, parse_url};
use http::h2::{
    connection_preface,
    decode_frame,
    frame_type_headers,
    frame_type_settings,
    h2_authority,
    h2_get_request_headers,
    h2_prior_knowledge_get,
    h2_status_from_headers,
    headers_from_frame,
};
use http::h2_session::{H2Session};

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

test("authority omits default ports and keeps others") {
    assert(h2_authority(must_url("http://example.com/")) == "example.com", "http80")?;
    assert(h2_authority(must_url("http://example.com:80/")) == "example.com", "http80 explicit")?;
    assert(h2_authority(must_url("http://example.com:8080/")) == "example.com:8080", "http custom")?;
    assert(h2_authority(must_url("https://example.com/")) == "example.com", "https443")?;
    assert(h2_authority(must_url("https://example.com:443/")) == "example.com", "https443 explicit")?;
    assert(h2_authority(must_url("https://example.com:8443/")) == "example.com:8443", "https custom")?;
}

test("get request headers carry path scheme and authority") {
    let h = h2_get_request_headers(must_url("http://api.example.com:9000/v1/x"));
    assert(h.count() == 4, "four")?;
    assert(h.name_at(0) == ":method", "method name")?;
    assert(h.value_at(0) == "GET", "GET")?;
    assert(h.name_at(1) == ":path", "path name")?;
    assert(h.value_at(1) == "/v1/x", "path")?;
    assert(h.name_at(2) == ":scheme", "scheme name")?;
    assert(h.value_at(2) == "http", "http")?;
    assert(h.name_at(3) == ":authority", "authority name")?;
    assert(h.value_at(3) == "api.example.com:9000", "host:port")?;
}

test("status from headers parses digits and defaults to 200") {
    let h404 = Headers::new();
    h404.add(":status", "404");
    assert(h2_status_from_headers(h404) == 404, "404")?;
    let h500 = Headers::new();
    h500.add("content-type", "text/plain");
    h500.add(":status", "500");
    assert(h2_status_from_headers(h500) == 500, "500 after other")?;
    let empty = Headers::new();
    assert(h2_status_from_headers(empty) == 200, "missing")?;
    let h200 = Headers::new();
    h200.add(":status", "200");
    assert(h2_status_from_headers(h200) == 200, "200")?;
}

test("prior knowledge wire is preface settings then stream-1 headers") {
    let u = must_url("http://example.com:8080/hello");
    let wire = h2_prior_knowledge_get(u);
    let pref = connection_preface();
    assert(len(wire) > len(pref), "longer than preface")?;
    let i = 0;
    while i < len(pref) {
        assert(wire[i] == pref[i], "preface bytes")?;
        i = i + 1;
    }
    let after = bytes_slice_after(wire, len(pref));
    let settings = match decode_frame(after) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "settings",
    };
    assert(settings.typ == frame_type_settings(), "settings type")?;
    assert(settings.stream_id == 0, "settings sid")?;
    let settings_len = 9 + len(settings.payload);
    let rest = bytes_slice_after(after, settings_len);
    let headers = match decode_frame(rest) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "headers",
    };
    assert(headers.typ == frame_type_headers(), "headers type")?;
    assert(headers.stream_id == 1, "stream 1")?;
    assert(headers.flags % 2 == 1, "END_STREAM")?;
    let decoded = match headers_from_frame(headers) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode headers",
    };
    assert(decoded.value_at(1) == "/hello", "path")?;
    assert(decoded.value_at(3) == "example.com:8080", "authority")?;
}

test("prior knowledge with custom port feeds session ended stream") {
    let u = must_url("http://127.0.0.1:9443/ping");
    let sess = H2Session::new();
    match sess.feed(h2_prior_knowledge_get(u)) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "feed",
    };
    assert(sess.stream_count() == 1, "one")?;
    let headers = match sess.stream_headers(1) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "headers",
    };
    assert(headers.value_at(1) == "/ping", "path")?;
    assert(headers.value_at(3) == "127.0.0.1:9443", "authority")?;
    let ended = match sess.stream_ended(1) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "ended",
    };
    assert(ended == 1, "ended")?;
    let ack = sess.drain();
    let ack_frame = match decode_frame(ack) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "ack",
    };
    assert(ack_frame.typ == frame_type_settings(), "ack settings")?;
    assert(ack_frame.flags % 2 == 1, "ACK flag")?;
}
