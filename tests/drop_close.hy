// GC-time drop closes sockets; explicit close_conn stays idempotent.
use gc::{collect};
use io::net::tcp::{listen};
use http::conn::{HttpConn, close_conn};
use http::client::Client;
use http::pool::ConnPool;
use http::server::Server;

fn leak_wrapped_listener() {
    let s = match listen("127.0.0.1", 0) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "listen",
    };
    let c = HttpConn::wrap(s);
}

fn leak_client() {
    let c = Client::new();
}

fn leak_pool() {
    let p = ConnPool::new();
}

fn leak_bound_server() {
    let srv = Server::new();
    match srv.bind("127.0.0.1", 0) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "bind",
    };
}

test("drop HttpConn without close_conn") {
    leak_wrapped_listener();
    collect();
}

test("close_conn then drop is idempotent") {
    let s = match listen("127.0.0.1", 0) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "listen",
    };
    let c = HttpConn::wrap(s);
    close_conn(c);
    c.drop();
    close_conn(c);
}

test("drop Client and ConnPool") {
    leak_client();
    leak_pool();
    collect();
}

test("drop Server then bind again") {
    leak_bound_server();
    collect();
    let srv = Server::new();
    match srv.bind("127.0.0.1", 0) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "rebind",
    };
}
