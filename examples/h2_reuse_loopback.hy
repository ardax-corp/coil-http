// 200 sequential Client::h2_get calls on one HTTP/2 connection.
// The server accepts once (`h2_serve_once`); a new TCP connect per GET would fail.
use thread::{Sender, channel, join, recv, send as thread_send, spawn};
use conv::{int_to_dec};
use string::{to_bytes};
use io::{stdout};
use io::sync::{write_all};
use http::client::Client;
use http::h1::IncomingRequest;
use http::response::Response;
use http::server::{HttpHandler, Server, h2_serve_once};

class OkHandler {}

impl HttpHandler<OkHandler> {
    fn handle(OkHandler self, IncomingRequest req) -> Response {
        let _m = req.method_val();
        let r = Response::ok();
        r.status(200);
        r.body(to_bytes("ok"));
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
    match h2_serve_once(srv, new OkHandler()) {
        Result::Ok(_) => 0,
        Result::Err(_) => 0,
    };
}

fn body_ok(Vec<byte> b) -> int {
    if len(b) != 2 {
        return 0;
    }
    if b[0] != ("o" as byte) {
        return 0;
    }
    if b[1] != ("k" as byte) {
        return 0;
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
    let c = Client::new();
    let i = 0;
    while i < 200 {
        match c.h2_get(url) {
            Result::Ok(r) => {
                if r.status != 200 {
                    panic "status";
                }
                if body_ok(r.body) == 0 {
                    panic "body";
                }
            },
            Result::Err(_) => panic "h2_get",
        };
        i = i + 1;
    }
    c.close();
    match join(t) {
        Result::Ok(_) => 0,
        Result::Err(_) => 0,
    };
    write_all(stdout(), to_bytes("ok"));
}
