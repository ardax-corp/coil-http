// h2_serve requires Server.tls; cleartext uses h2_serve_once.
use http::server::{Server, h2_serve};

test("h2_serve without tls is NotSupported") {
    let srv = Server::new();
    let r = h2_serve(srv);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "need tls")?;
}
