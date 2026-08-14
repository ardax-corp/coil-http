// Two GETs on one keep-alive connection (pool).
use thread::{Sender, channel, join, recv, send as thread_send, spawn};
use conv::{int_to_dec};
use string::{to_bytes};
use io::{stdout};
use io::sync::{write_all};
use http::client::Client;
use http::server::{Server, HttpHandler, serve_one_client};
use http::h1::IncomingRequest;
use http::response::Response;

class OkHandler {}

impl HttpHandler<OkHandler> {
    fn handle(OkHandler self, IncomingRequest req) -> Response {
        let r = Response::ok();
        r.header("Content-Type", "text/plain");
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
    let h = new OkHandler();
    match serve_one_client(srv, h) {
        Result::Ok(_) => 0,
        Result::Err(_) => 0,
    };
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
    match c.get(url) {
        Result::Ok(r) => 0,
        Result::Err(_) => panic "get1",
    };
    match c.get(url) {
        Result::Ok(r) => {
            write_all(stdout(), to_bytes("ok"));
        },
        Result::Err(_) => panic "get2",
    };
    c.close();
    match join(t) {
        Result::Ok(_) => 0,
        Result::Err(_) => 0,
    };
}
