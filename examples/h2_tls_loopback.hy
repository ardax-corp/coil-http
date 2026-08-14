// HTTPS HTTP/2 ALPN loopback (needs coil client+server TLS handshake across threads).
// Blocked on coil-lang dual-TLS until that works; not run in CI.
use thread::{Sender, channel, join, recv, send as thread_send, spawn};
use conv::{int_to_dec};
use string::{to_bytes};
use io::{stdout, open, close as io_close};
use io::sync::{write_all, read_to_end};
use http::url::{bytes_to_string};
use http::h2::{h2_connect_tls};
use http::server::{Server, h2_serve};

fn load_pem(string path) -> string {
    let s = match open(path, "r") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "open",
    };
    let b = match read_to_end(s) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "read",
    };
    match io_close(s) {
        Result::Ok(_) => 0,
        Result::Err(_) => 0,
    };
    return match bytes_to_string(b) {
        Result::Ok(t) => t,
        Result::Err(_) => panic "utf8",
    };
}

fn server_thread(Sender tx) {
    let srv = Server::new();
    match srv.bind("127.0.0.1", 0) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "bind",
    };
    srv.tls(
        load_pem("examples/testdata/h2_loopback.crt"),
        load_pem("examples/testdata/h2_loopback.key"),
    );
    let port = match srv.bound_port() {
        Result::Ok(p) => p,
        Result::Err(_) => panic "port",
    };
    match thread_send(tx, port) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "send port",
    };
    match h2_serve(srv) {
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
    let url = "https://127.0.0.1:" + int_to_dec(port) + "/";
    match h2_connect_tls(url, false, "") {
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
        Result::Err(_) => panic "h2_connect_tls",
    };
    match join(t) {
        Result::Ok(_) => 0,
        Result::Err(_) => 0,
    };
}
