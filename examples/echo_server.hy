// Echo server: responds 200 with body "ok" for each request.
use http::server::{Server, HttpHandler, serve_once};
use http::h1::IncomingRequest;
use http::response::Response;
use string::{to_bytes};

class EchoHandler {}

impl HttpHandler<EchoHandler> {
    fn handle(EchoHandler self, IncomingRequest req) -> Response {
        let r = Response::ok();
        r.header("Content-Type", "text/plain");
        r.body(to_bytes("ok"));
        return r;
    }
}

fn main() {
    let port = 41250;
    let srv = Server::new();
    srv.bind("127.0.0.1", port)?;
    let h = new EchoHandler();
    serve_once(srv, h)?;
}
