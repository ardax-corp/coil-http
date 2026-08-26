// Two concurrent GETs on one cleartext HTTP/2 session (streams 1 and 3).
use thread::{Sender, channel, join, recv, send as thread_send, spawn};
use conv::{int_to_dec};
use string::{to_bytes};
use io::{stdout};
use io::sync::{write_all};
use http::h2::{h2_connect_two};
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
    let a = "http://127.0.0.1:" + int_to_dec(port) + "/a";
    let b = "http://127.0.0.1:" + int_to_dec(port) + "/b";
    match h2_connect_two(a, b) {
        Result::Ok(r) => {
            if r.first.status == 200 {
                if r.second.status == 200 {
                    if body_ok(r.first.body) == 1 {
                        if body_ok(r.second.body) == 1 {
                            write_all(stdout(), to_bytes("ok"));
                        }
                    }
                }
            }
        },
        Result::Err(_) => panic "h2_connect_two",
    };
    match join(t) {
        Result::Ok(_) => 0,
        Result::Err(_) => 0,
    };
}
