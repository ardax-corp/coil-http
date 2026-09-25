// h2_serve requires Server.tls; cleartext uses h2_serve_once.
use http::h1::IncomingRequest;
use http::response::Response;
use http::server::{HttpHandler, Server, h2_serve};

class DenyHandler {}

impl HttpHandler for DenyHandler {
    fn handle(DenyHandler self, IncomingRequest req) -> Response {
        let _m = req.method_val();
        return Response::ok();
    }
}

test("h2_serve without tls is NotSupported") {
    let srv = Server::new();
    let r = h2_serve(srv, new DenyHandler());
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "need tls")?;
}
