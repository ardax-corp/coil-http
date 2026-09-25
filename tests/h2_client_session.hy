// HTTP/2 session on Client is separate from the HTTP/1.1 pool.
use http::client::Client;
use http::h2_session::{h2_slot_close, h2_slot_empty, h2_origin_key};
use http::url::{parse_url};

test("empty h2 slot close is idempotent") {
    let s = h2_slot_empty();
    h2_slot_close(s);
    h2_slot_close(s);
}

test("h2 origin key is scheme host port") {
    let u = match parse_url("http://127.0.0.1:9/") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "url",
    };
    assert(h2_origin_key(u) == "http://127.0.0.1:9", "key")?;
}

test("https origin key keeps the scheme") {
    let u = match parse_url("https://api.example.com/v1") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "url",
    };
    assert(h2_origin_key(u) == "https://api.example.com:443", "https key")?;
}

test("Client close drains the h2 slot") {
    let c = Client::new();
    c.close();
    c.close();
}
