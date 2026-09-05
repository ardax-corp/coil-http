// WebSocket echo loopback (RFC 6455). Needs thread::spawn; coil test cannot.
use thread::{Sender, channel, join, recv, send as thread_send, spawn};
use conv::{int_to_dec};
use string::{to_bytes};
use io::{stdout};
use io::sync::{write_all};
use http::server::{Server};
use http::ws::{
    ws_close,
    ws_connect,
    ws_echo_loop,
    ws_opcode_bin,
    ws_opcode_text,
    ws_recv,
    ws_send_bin,
    ws_send_close,
    ws_send_ping,
    ws_send_text,
    ws_serve_once,
};

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
    let c = match ws_serve_once(srv) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "upgrade",
    };
    match ws_echo_loop(c) {
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
    let url = "ws://127.0.0.1:" + int_to_dec(port) + "/echo";
    let c = match ws_connect(url) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "connect",
    };
    match ws_send_text(c, "hello") {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "send text",
    };
    let t1 = match ws_recv(c) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "recv text",
    };
    if t1.opcode != ws_opcode_text() {
        panic "not text";
    }
    if len(t1.payload) != 5 {
        panic "text len";
    }
    match ws_send_bin(c, to_bytes("ok")) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "send bin",
    };
    let t2 = match ws_recv(c) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "recv bin",
    };
    if t2.opcode != ws_opcode_bin() {
        panic "not bin";
    }
    match ws_send_ping(c, to_bytes("p")) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "ping",
    };
    let t3 = match ws_recv(c) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "pong",
    };
    if t3.opcode != 10 {
        panic "not pong";
    }
    match ws_send_close(c) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "close",
    };
    match ws_recv(c) {
        Result::Ok(_) => 0,
        Result::Err(_) => 0,
    };
    ws_close(c);
    match join(t) {
        Result::Ok(_) => 0,
        Result::Err(_) => 0,
    };
    match write_all(stdout(), to_bytes("ok")) {
        Result::Ok(_) => 0,
        Result::Err(_) => 0,
    };
}
