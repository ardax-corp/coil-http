// Cleartext HTTP/2 prior-knowledge loopback.
// The server dispatches each stream to a handler; the client prints that status and body.
use thread::{Sender, channel, join, recv, send as thread_send, spawn};
use conv::{int_to_dec};
use string::{to_bytes};
use io::{stdout};
use io::sync::{write_all};
use http::h1::IncomingRequest;
use http::response::Response;
use http::h2_session::{h2_connect};
use http::server::{HttpHandler, Server, h2_serve_once};

class DemoHandler {}

impl HttpHandler<DemoHandler> {
    fn handle(DemoHandler self, IncomingRequest req) -> Response {
        let _path = req.path_val();
        let r = Response::ok();
        r.status(201);
        r.header("x-from", "handler");
        r.body(to_bytes("from-handler"));
        return r;
    }
}

fn server_thread(Sender tx) {
    let srv = Server::new();
    match srv.bind("127.0.0.1", 0) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "bind",
    };
    let port = match srv.bound_port() {
        Result::Ok(p) => p,
        Result::Err(_) => panic "port",
    };
    match thread_send(tx, port) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "send port",
    };
    match h2_serve_once(srv, new DemoHandler()) {
        Result::Ok(_) => 0,
        Result::Err(_) => 0,
    };
}

fn body_is(Vec<byte> b, string s) -> int {
    let want = to_bytes(s);
    if len(b) != len(want) {
        return 0;
    }
    let i = 0;
    while i < len(b) {
        if b[i] != want[i] {
            return 0;
        }
        i = i + 1;
    }
    return 1;
}

fn main() {
    let pair = match channel() {
        Result::Ok(p) => p,
        Result::Err(_) => panic "channel",
    };
    let t = match spawn(server_thread, pair[0]) {
        Result::Ok(th) => th,
        Result::Err(_) => panic "spawn",
    };
    let port = match recv(pair[1]) {
        Result::Ok(p) => p,
        Result::Err(_) => panic "recv",
    };
    let url = "http://127.0.0.1:" + int_to_dec(port) + "/";
    match h2_connect(url) {
        Result::Ok(r) => {
            if r.status != 201 {
                panic "status";
            }
            if body_is(r.body, "from-handler") == 0 {
                panic "body";
            }
            write_all(stdout(), to_bytes("status=201\nbody=from-handler\nok"));
        },
        Result::Err(_) => panic "h2_connect",
    };
    match join(t) {
        Result::Ok(_) => 0,
        Result::Err(_) => 0,
    };
}
