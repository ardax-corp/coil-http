// 200 sequential one-shot `h2_connect` calls (new TCP connection each GET).
use thread::{Sender, channel, join, recv, send as thread_send, spawn};
use conv::{int_to_dec};
use string::{to_bytes};
use io::{stdout};
use io::sync::{write_all};
use http::h1::IncomingRequest;
use http::response::Response;
use http::h2_session::{h2_connect};
use http::server::{HttpHandler, Server, h2_serve_once};

class OkHandler {}

impl HttpHandler for OkHandler {
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
    let i = 0;
    while i < 200 {
        match h2_serve_once(srv, new OkHandler()) {
            Result::Ok(_) => 0,
            Result::Err(_) => 0,
        };
        i = i + 1;
    }
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
    let i = 0;
    while i < 200 {
        match h2_connect(url) {
            Result::Ok(r) => {
                if r.status != 200 {
                    panic "status";
                }
            },
            Result::Err(_) => panic "h2_connect",
        };
        i = i + 1;
    }
    match join(t) {
        Result::Ok(_) => 0,
        Result::Err(_) => 0,
    };
    write_all(stdout(), to_bytes("ok"));
}
