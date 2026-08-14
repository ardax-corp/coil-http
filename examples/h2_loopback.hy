// Cleartext HTTP/2 prior-knowledge loopback (RFC 7540 §3.4).
use thread::{Sender, channel, join, recv, send as thread_send, spawn};
use conv::{int_to_dec};
use string::{to_bytes};
use io::{stdout};
use io::sync::{write_all};
use http::h2::{h2_connect};
use http::server::{Server, h2_serve_once};

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
    match h2_serve_once(srv) {
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
    match h2_connect(url) {
        Result::Ok(r) => {
            if r.status == 200 {
                if len(r.body) == 2 {
                    if r.body[0] == ("o" as byte) {
                        if r.body[1] == ("k" as byte) {
                            write_all(stdout(), to_bytes("ok"));
                        }
                    }
                }
            }
        },
        Result::Err(_) => panic "h2_connect",
    };
    match join(t) {
        Result::Ok(_) => 0,
        Result::Err(_) => 0,
    };
}
