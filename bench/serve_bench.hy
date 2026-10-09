// `serve` (a task per connection) against a one-connection-at-a-time loop.
// Clients are tasks in the same VM. Prints wall milliseconds per case:
//   fast:  N clients, one request each (accept/spawn overhead)
//   slow:  K keep-alive clients, two requests 20 ms apart (concurrency)
// A thread-per-connection server cannot be written yet: a `Stream` is not
// sendable to `thread::spawn`. Keep "fast" under the 128 listen backlog:
// client connects block the VM thread (coil-lang#832).
use clock::mono_nanos;
use conv::{int_to_dec};
use string::{to_bytes};
use io::{stdout, Stream, close as io_close};
use io::net::tcp::connect;
use io::sync::{accept_wait, write_all};
use http::server::{Server, HttpHandler, serve, serve_conn_loop};
use http::conn::{HttpConn, close_conn, read_http_message};
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

// The accept loop before tasks: one connection at a time.
fn serve_sequential(Stream listener, HttpHandler handler) -> int {
    let keep = true;
    while keep {
        match accept_wait(listener) {
            Result::Ok(conn) => {
                let _ = serve_conn_loop(conn, handler);
            },
            Result::Err(_) => {
                keep = false;
            },
        }
    }
    return 0;
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

fn client(int port, int gap_ms) -> int {
    let s = match connect("127.0.0.1", port) {
        Result::Ok(s) => s,
        Result::Err(_) => panic "connect",
    };
    let c = HttpConn::wrap(s);
    let keep = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";
    let last = "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n";
    let n = 0;
    if gap_ms > 0 {
        n = exchange(c, keep);
        task::sleep(gap_ms);
    }
    n = n + exchange(c, last);
    close_conn(c);
    return n;
}

fn got(Task<int> t) -> int {
    return match t.join() {
        Result::Ok(n) => n,
        Result::Err(_) => 0,
    };
}

// Run `clients` clients against a fresh server; wall milliseconds.
fn run(bool tasks, int clients, int gap_ms) -> int {
    let srv = Server::new();
    match srv.bind("127.0.0.1", 0) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "bind",
    };
    let port = match srv.bound_port() {
        Result::Ok(p) => p,
        Result::Err(_) => panic "port",
    };
    let listener = match srv.listener {
        Option::Some(l) => l,
        Option::None => panic "listener",
    };
    let start = mono_nanos();
    let _ = scope(
        fn (Scope s) use (srv, listener, port, tasks, clients, gap_ms) {
            let server = s.spawn(fn () use (srv, listener, tasks) {
                if tasks {
                    let _ = serve(srv, new OkHandler());
                } else {
                    serve_sequential(listener, new OkHandler());
                }
                0
            });
            let all: Vec<Task<int>> = Vec::new();
            let i = 0;
            while i < clients {
                all.push(s.spawn(fn () use (port, gap_ms) => client(port, gap_ms)));
                i = i + 1;
            }
            let ok = 0;
            for t in all {
                if got(t) > 0 {
                    ok = ok + 1;
                }
            }
            if ok != clients {
                panic "a client failed";
            }
            server.cancel();
            0
        },
    );
    let _ = io_close(listener);
    return (mono_nanos() - start) / 1000000;
}

fn line(string name, int ms) {
    write_all(stdout(), to_bytes(name + ": " + int_to_dec(ms) + " ms\n"));
}

fn main() {
    line("fast sequential (100 clients)", run(false, 100, 0));
    line("fast tasks      (100 clients)", run(true, 100, 0));
    line("slow sequential (20 clients) ", run(false, 20, 20));
    line("slow tasks      (20 clients) ", run(true, 20, 20));
}
