// GC-time drop closes sockets; explicit close_conn stays idempotent.
use gc::{collect};
use io::{Stream};
use io::net::tcp::{listen};
use http::conn::{HttpConn, close_conn};
use http::client::Client;
use http::pool::ConnPool;
use http::server::Server;
use http::url::{parse_url};

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

fn listen_stream() -> Stream {
    return match listen("127.0.0.1", 0) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "listen",
    };
}

test("drop HttpConn without close_conn") {
    leak_wrapped_listener();
    collect();
}

test("close_conn then drop is idempotent") {
    let s = listen_stream();
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

test("wrap starts open; close_conn sets closed") {
    let c = HttpConn::wrap(listen_stream());
    assert(c.closed == 0, "wrap starts open")?;
    close_conn(c);
    assert(c.closed == 1, "close_conn marks closed")?;
}

test("drop then close_conn is idempotent") {
    let c = HttpConn::wrap(listen_stream());
    c.drop();
    assert(c.closed == 1, "drop marks closed")?;
    close_conn(c);
    c.drop();
    assert(c.closed == 1, "stays closed")?;
}

test("ConnPool drop closes released sockets") {
    let c = HttpConn::wrap(listen_stream());
    let p = ConnPool::new();
    let u = match parse_url("http://127.0.0.1:9/") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "url",
    };
    p.release(u, c);
    assert(c.closed == 0, "pooled stays open")?;
    p.drop();
    assert(c.closed == 1, "pool drop closes")?;
}

test("Client close then drop is idempotent") {
    let c = Client::new();
    c.close();
    c.drop();
    c.close();
}

test("Server drop unbound and rebind same instance") {
    let srv = Server::new();
    srv.drop();
    match srv.bind("127.0.0.1", 0) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "bind after unbound drop",
    };
    srv.drop();
    srv.drop();
    match srv.bind("127.0.0.1", 0) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "rebind after drop",
    };
}
