// `serve` runs each connection in its own task: three keep-alive clients
// that each wait 100 ms between two requests are served together, not one
// after another. The server task is cancelled once the clients are done.
use clock::mono_nanos;
use conv::{int_to_dec};
use string::{to_bytes};
use io::{stdout};
use io::net::tcp::connect;
use io::sync::{write_all};
use http::conn::{HttpConn, close_conn, read_http_message};
use http::server::{Server, HttpHandler, serve};
use http::h1::IncomingRequest;
use http::response::Response;
use task::{scope, Scope, Task};

class OkHandler {}

impl HttpHandler for OkHandler {
    fn handle(OkHandler self, IncomingRequest req) -> Response {
        let r = Response::ok();
        r.header("Content-Type", "text/plain");
        r.body(to_bytes("ok"));
        return r;
    }
}

// Two requests on one keep-alive connection, `ms` apart. A server that
// serves one connection at a time holds the others back meanwhile.
fn slow_client(int port, int ms) -> int {
    let s = match connect("127.0.0.1", port) {
        Result::Ok(s) => s,
        Result::Err(_) => panic "connect",
    };
    let c = HttpConn::wrap(s);
    let keep = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";
    let last = "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n";
    let n = exchange(c, keep);
    task::sleep(ms);
    n = n + exchange(c, last);
    close_conn(c);
    return n;
}

fn exchange(HttpConn c, string req) -> int {
    match write_all(c.stream(), to_bytes(req)) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "write",
    };
    return match read_http_message(c) {
        Result::Ok(b) => len(b),
        Result::Err(_) => 0,
    };
}

fn got(Task<int> t) -> int {
    return match t.join() {
        Result::Ok(n) => n,
        Result::Err(_) => 0,
    };
}

fn main() {
    let srv = Server::new();
    match srv.bind("127.0.0.1", 0) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "bind",
    };
    let port = match srv.bound_port() {
        Result::Ok(p) => p,
        Result::Err(_) => panic "port",
    };
    let start = mono_nanos();
    let r = scope(
        fn (Scope s) use (srv, port) {
            let server = s.spawn(fn () use (srv) {
                let _ = serve(srv, new OkHandler());
                0
            });
            let a = s.spawn(fn () use (port) => slow_client(port, 100));
            let b = s.spawn(fn () use (port) => slow_client(port, 100));
            let c = s.spawn(fn () use (port) => slow_client(port, 100));
            let ok = got(a) > 0 && got(b) > 0 && got(c) > 0;
            server.cancel();
            ok
        },
    );
    let ms = (mono_nanos() - start) / 1000000;
    let text = match r {
        Result::Ok(true) => "ok",
        default => "failed",
    };
    // One after another would take at least 300 ms.
    if ms >= 280 {
        text = "slow: " + int_to_dec(ms) + " ms";
    }
    write_all(stdout(), to_bytes(text));
}
