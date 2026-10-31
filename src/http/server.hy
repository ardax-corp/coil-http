// HTTP/1.1 cleartext/TLS server.
use io::{Stream, close as io_close};
use string::{to_bytes};
use io::net::tcp::{listen, local_addr};
use tls::server::{enable as tls_server_enable, ServerOpts};
use tls::{alpn_protocol};
use io::sync::{accept_wait, write_all};
use task::{scope, Scope};

use http::url::{HttpError, Headers, http_err_protocol, http_err_not_supported, http_fail_stream, http_fail_unit, http_fail_tls, http_fail_tls_unit, http_not_bound};
use http::h1::{IncomingRequest, encode_response, encode_response_keepalive, incoming_wants_close, parse_request};
use http::response::{Response};
use http::conn::{HttpConn, close_conn, read_http_message};
use http::h2::{
    H2Settings,
    encode_frame,
    h2_alpn_is_h2,
    h2_read_frame,
    h2_read_n,
    h2_server_alpn,
    h2_try_read_frame,
    settings_id_enable_push,
};
use http::h2_session::{H2Session};

/// Answers server requests: implement `handle` and pass the value to `serve` (or
/// another serve function).
///
/// `handle` runs once per request, on HTTP/1.1 and HTTP/2 alike, and cannot fail:
/// turn errors into a status code. `serve` runs each connection in its own task,
/// so one handler value may be called from several tasks at once.
///
/// # Examples
///
/// ```
/// # use tests::assert;
/// use http::server::HttpHandler;
/// use http::h1::{IncomingRequest, parse_request};
/// use http::response::Response;
/// use string::to_bytes;
///
/// class Hello {}
///
/// impl HttpHandler for Hello {
///     fn handle(Hello self, IncomingRequest req) -> Response {
///         let r = Response::ok();
///         if req.path_val() != "/" {
///             r.status(404);
///             return r;
///         }
///         r.header("Content-Type", "text/plain");
///         r.body(to_bytes("hello"));
///         return r;
///     }
/// }
///
/// fn main() {
///     let h = new Hello();
///     let req = match parse_request(to_bytes("GET /missing HTTP/1.1\r\nHost: x\r\n\r\n")) {
///         Result::Ok(r) => r,
///         Result::Err(e) => panic show(e),
///     };
///     assert!(h.handle(req).status == 404);
/// }
/// ```
trait HttpHandler<H> {
    /// Builds the response to `req`.
    fn handle(H self, IncomingRequest req) -> Response;
}

/// A listening HTTP server socket and its TLS settings.
///
/// `bind` opens the listener; `tls` turns on TLS for accepted connections. Then
/// hand the server and an `HttpHandler` to one of the serve functions:
///
/// | Function | Accepts | Protocol |
/// |---|---|---|
/// | `serve` | until the listener fails, a task per connection | HTTP/1.1, keep-alive |
/// | `serve_once` | one connection, one request | HTTP/1.1 |
/// | `serve_one_client` | one connection, until it closes | HTTP/1.1, keep-alive |
/// | `h2_serve_all` | until the listener fails, one connection at a time | HTTP/2 (prior knowledge, or TLS ALPN `h2`), else HTTP/1.1 |
/// | `h2_serve` | as `h2_serve_all`, TLS only | HTTP/2 or HTTP/1.1 by ALPN |
/// | `h2_serve_once` | one connection | as `h2_serve_all` |
///
/// `http::ws::ws_serve_once` accepts a WebSocket upgrade on the same listener.
/// The program needs `--allow-net`, and with TLS also `--allow-attach` and the
/// `libtls` grants. Dropping the server closes the listener only when the
/// garbage collector runs.
///
/// # Examples
///
/// ```no_run
/// use http::server::{HttpHandler, Server, serve};
/// use http::h1::IncomingRequest;
/// use http::response::Response;
/// use http::url::HttpError;
/// use string::to_bytes;
///
/// class Hello {}
///
/// impl HttpHandler for Hello {
///     fn handle(Hello self, IncomingRequest req) -> Response {
///         let r = Response::ok();
///         r.header("Content-Type", "text/plain");
///         r.body(to_bytes("hello from " + req.path_val()));
///         return r;
///     }
/// }
///
/// fn main() -> Result<(), HttpError> {
///     let srv = Server::new();
///     srv.bind("127.0.0.1", 8080)?;
///     serve(srv, new Hello())?;
///     return ();
/// }
/// ```
class Server {
    /// Host the listener was bound to (`127.0.0.1` before `bind`).
    pub host: string,
    /// Port passed to `bind`; `0` means the system picked one (see `bound_port`).
    pub port: int,
    /// The listening socket, `None` until `bind` succeeds.
    pub listener: Option<Stream>,
    /// PEM certificate chain set by `tls`.
    pub tls_cert: string,
    /// PEM private key set by `tls`.
    pub tls_key: string,
    /// 1 when `tls` was called and accepted connections do a TLS handshake.
    pub use_tls: int,
}

impl Server {
    /// An unbound server without TLS.
    pub static fn new() -> Server {
        return new Server("127.0.0.1", 0, Option::None, "", "", 0);
    }

    /// Starts listening on `host:port`. Port `0` picks a free port; read it with
    /// `bound_port`. Returns `Io` when the address cannot be bound.
    pub fn bind(string host, int port) -> Result<(), HttpError> {
        let listener = match listen(host, port) {
            Result::Ok(s) => s,
            Result::Err(e) => http_fail_stream(e)?,
        };
        self.host = host;
        self.port = port;
        self.listener = Option::Some(listener);
        return ();
    }

    /// Serves TLS with this PEM certificate chain and private key.
    ///
    /// The handshake runs per accepted connection, so a bad certificate or key shows
    /// up when a client connects, not here.
    pub fn tls(string cert_pem, string key_pem) {
        self.tls_cert = cert_pem;
        self.tls_key = key_pem;
        self.use_tls = 1;
    }

    /// The port the listener is bound to; useful after `bind(host, 0)`.
    ///
    /// Returns `Io(InvalidInput)` before `bind`.
    ///
    /// # Examples
    ///
    /// ```no_run
    /// use http::server::Server;
    /// use http::url::HttpError;
    ///
    /// fn main() -> Result<(), HttpError> {
    ///     let srv = Server::new();
    ///     srv.bind("127.0.0.1", 0)?;
    ///     let port = srv.bound_port()?;
    ///     return ();
    /// }
    /// ```
    pub fn bound_port() -> Result<int, HttpError> {
        if match self.listener {
            Option::None => true,
            Option::Some(_) => false,
        } {
            http_not_bound()?;
            return 0;
        }
        let s = match self.listener {
            Option::Some(v) => v,
            Option::None => http_not_bound()?,
        };
        let addr = match local_addr(s) {
            Result::Ok(t) => t,
            Result::Err(e) => {
                http_fail_unit(e)?;
                return 0;
            },
        };
        let (_, port) = addr;
        return port;
    }

    fn drop() {
        match self.listener {
            Option::None => 0,
            Option::Some(s) => {
                match io_close(s) {
                    Result::Ok(_) => 0,
                    Result::Err(_) => 0,
                };
                self.listener = Option::None;
                0
            },
        };
        self.use_tls = self.use_tls;
    }
}

fn serve_conn_once(Server srv, Stream s, HttpHandler handler) -> Result<(), HttpError> {
    let c = HttpConn::wrap(s);
    let raw = read_http_message(c)?;
    let req = parse_request(raw)?;
    let resp = handle(handler, req);
    let wire = encode_response(resp);
    match write_all(c.stream(), wire) {
        Result::Ok(_) => 0,
        Result::Err(_) => 0,
    };
    close_conn(c);
    return ();
}

/// Accepts one connection, answers one HTTP/1.1 request with `handler`, and
/// closes the connection.
///
/// Returns `Io(InvalidInput)` when `srv` is not bound, `Io` when accepting
/// fails, `Tls` when the handshake fails and `Protocol` for a malformed request.
fn serve_once(Server srv, HttpHandler handler) -> Result<(), HttpError> {
    let listener = match srv.listener {
        Option::None => http_not_bound()?,
        Option::Some(s) => s,
    };
    let conn = match accept_wait(listener) {
        Result::Ok(s) => s,
        Result::Err(e) => http_fail_stream(e)?,
    };
    let stream = conn;
    if srv.use_tls == 1 {
        stream = match tls_server_enable(conn, new ServerOpts(srv.tls_cert, srv.tls_key, 0, "", "")) {
            Result::Ok(s) => s,
            Result::Err(e) => http_fail_tls(e)?,
        };
    }
    return serve_conn_once(srv, stream, handler)?;
}

/// Serves HTTP/1.1 requests on an accepted stream until the client closes, sends
/// `Connection: close`, or sends a malformed request, then closes the stream.
fn serve_conn_loop(Stream s, HttpHandler handler) -> Result<(), HttpError> {
    let c = HttpConn::wrap(s);
    let keep_going = 1;
    while keep_going == 1 {
        let raw_ok = 0;
        let raw = match read_http_message(c) {
            Result::Ok(b) => {
                raw_ok = 1;
                b
            },
            Result::Err(_) => {
                raw_ok = 0;
                Vec::new()
            },
        };
        if raw_ok == 0 {
            keep_going = 0;
        } else {
            let req = match parse_request(raw) {
                Result::Ok(r) => r,
                Result::Err(_) => {
                    keep_going = 0;
                    new IncomingRequest("", "", "", Headers::new(), raw)
                },
            };
            if keep_going == 1 {
                let resp = handle(handler, req);
                let wire = encode_response(resp);
                if incoming_wants_close(req) == 0 {
                    wire = encode_response_keepalive(resp);
                }
                match write_all(c.stream(), wire) {
                    Result::Ok(_) => 0,
                    Result::Err(_) => {
                        keep_going = 0;
                        0
                    },
                };
                if incoming_wants_close(req) == 1 {
                    keep_going = 0;
                }
            }
        }
    }
    close_conn(c);
    return ();
}

/// Accepts one connection and serves HTTP/1.1 on it until the client closes or
/// sends `Connection: close`.
///
/// Returns `Io(InvalidInput)` when `srv` is not bound and `Io` / `Tls` when
/// accepting or the handshake fails.
fn serve_one_client(Server srv, HttpHandler handler) -> Result<(), HttpError> {
    let listener = match srv.listener {
        Option::None => http_not_bound()?,
        Option::Some(s) => s,
    };
    let conn = match accept_wait(listener) {
        Result::Ok(s) => s,
        Result::Err(e) => http_fail_stream(e)?,
    };
    let stream = conn;
    if srv.use_tls == 1 {
        stream = match tls_server_enable(conn, new ServerOpts(srv.tls_cert, srv.tls_key, 0, "", "")) {
            Result::Ok(s) => s,
            Result::Err(e) => http_fail_tls(e)?,
        };
    }
    return serve_conn_loop(stream, handler)?;
}

// One accepted connection, in its own task: TLS handshake (when enabled),
// then HTTP/1.1 until the client closes.
fn serve_accepted(Server srv, Stream conn, HttpHandler handler) -> int {
    let stream = conn;
    if srv.use_tls == 1 {
        stream = match tls_server_enable(conn, new ServerOpts(srv.tls_cert, srv.tls_key, 0, "", "")) {
            Result::Ok(s) => s,
            Result::Err(_) => {
                match io_close(conn) {
                    Result::Ok(_) => 0,
                    Result::Err(_) => 0,
                };
                return 0;
            },
        };
    }
    match serve_conn_loop(stream, handler) {
        Result::Ok(_) => 0,
        Result::Err(_) => 0,
    };
    return 0;
}

/// Serves HTTP/1.1 until accepting fails, each connection in its own task.
///
/// A slow client or TLS handshake does not hold up the others. A connection is
/// kept open until the client closes it or sends `Connection: close`; per
/// connection errors only end that connection. Every connection's task calls the
/// same `handler` object. Returns `Io(InvalidInput)` when `srv` is not bound;
/// otherwise returns once `accept` fails and the open connections are done,
/// after closing the listener.
fn serve(Server srv, HttpHandler handler) -> Result<(), HttpError> {
    let listener = match srv.listener {
        Option::None => http_not_bound()?,
        Option::Some(s) => s,
    };
    let _ = scope(
        fn (Scope s) use (srv, listener, handler) {
            let keep = 1;
            while keep == 1 {
                match accept_wait(listener) {
                    Result::Ok(conn) => {
                        s.spawn(fn () use (srv, conn, mut handler) => serve_accepted(srv, conn, handler));
                    },
                    Result::Err(_) => {
                        keep = 0;
                    },
                }
            }
            0
        },
    );
    match io_close(listener) {
        Result::Ok(_) => 0,
        Result::Err(_) => 0,
    };
    return ();
}

fn h2_close_stream(Stream s) {
    match io_close(s) {
        Result::Ok(_) => 0,
        Result::Err(_) => 0,
    };
}

fn h2_write_bytes(Stream s, Vec<byte> wire) -> Result<(), HttpError> {
    if wire.len() == 0 {
        return ();
    }
    match write_all(s, wire) {
        Result::Ok(_) => 0,
        Result::Err(e) => {
            http_fail_unit(e)?;
            0
        },
    };
    return ();
}

fn h2_int_has(Vec<int> v, int x) -> int {
    let i = 0;
    while i < v.len() {
        if v[i] == x {
            return 1;
        }
        i = i + 1;
    }
    return 0;
}

fn h2_header_named(Headers h, string name) -> string {
    let i = 0;
    let n = h.count();
    while i < n {
        if h.name_at(i) == name {
            return h.value_at(i);
        }
        i = i + 1;
    }
    return "";
}

fn h2_request_from_stream(H2Session sess, int sid) -> Result<IncomingRequest, HttpError> {
    let h = sess.stream_headers(sid)?;
    let method = h2_header_named(h, ":method");
    let path = h2_header_named(h, ":path");
    let host = h2_header_named(h, ":authority");
    let fields = Headers::new();
    if host != "" {
        fields.add("Host", host);
    }
    let i = 0;
    let n = h.count();
    while i < n {
        let name = h.name_at(i);
        if name != ":method" {
            if name != ":path" {
                if name != ":scheme" {
                    if name != ":authority" {
                        fields.add(name, h.value_at(i));
                    }
                }
            }
        }
        i = i + 1;
    }
    let body = sess.stream_body(sid)?;
    return new IncomingRequest(method, path, "HTTP/2", fields, body);
}

fn h2_dispatch_ready(H2Session sess, HttpHandler handler, Vec<int> done_ids) -> Result<(), HttpError> {
    let n = sess.stream_count();
    let i = 0;
    while i < n {
        let sid = sess.stream_id_at(i)?;
        let ended = sess.stream_ended(sid)?;
        let rst = sess.stream_reset(sid)?;
        if ended == 1 {
            if rst == 0 {
                if h2_int_has(done_ids, sid) == 0 {
                    let req = h2_request_from_stream(sess, sid)?;
                    let resp = handle(handler, req);
                    let fields = Headers::new();
                    let hi = 0;
                    while hi < resp.header_names.len() {
                        fields.add(resp.header_names[hi], resp.header_values[hi]);
                        hi = hi + 1;
                    }
                    let trails = Headers::new();
                    let ti = 0;
                    while ti < resp.trailer_names.len() {
                        trails.add(resp.trailer_names[ti], resp.trailer_values[ti]);
                        ti = ti + 1;
                    }
                    sess.queue_response(sid, resp.status, fields, resp.body, trails)?;
                    done_ids.push(sid);
                }
            }
        }
        i = i + 1;
    }
    return ();
}

fn h2_streams_settled(H2Session sess, Vec<int> answered) -> int {
    let n = sess.stream_count();
    if n == 0 {
        if sess.goaway_received() == 1 {
            return 1;
        }
        return 0;
    }
    let last = sess.goaway_last_stream();
    let i = 0;
    while i < n {
        let sid = match sess.stream_id_at(i) {
            Result::Ok(v) => v,
            Result::Err(_) => {
                return 0;
            },
        };
        if sid <= last {
            let ended = match sess.stream_ended(sid) {
                Result::Ok(v) => v,
                Result::Err(_) => 0,
            };
            if ended == 0 {
                return 0;
            }
            let rst = match sess.stream_reset(sid) {
                Result::Ok(v) => v,
                Result::Err(_) => 0,
            };
            if rst == 0 {
                if h2_int_has(answered, sid) == 0 {
                    return 0;
                }
            }
        }
        i = i + 1;
    }
    return 1;
}

fn h2_arm_server(H2Session sess) -> Result<(), HttpError> {
    let st = H2Settings::new();
    st.add(settings_id_enable_push(), 0);
    return sess.queue_local_settings(st)?;
}

/// Speaks prior-knowledge HTTP/2 on an already accepted stream, answering each
/// finished stream with `handler`, until the client closes or the session ends
/// after `GOAWAY`. Closes the stream when done; returns `Protocol` (after sending
/// `GOAWAY`) when the client breaks HTTP/2.
fn h2_serve_conn(Stream conn, HttpHandler handler) -> Result<(), HttpError> {
    let sess = H2Session::new();
    match h2_arm_server(sess) {
        Result::Ok(_) => 0,
        Result::Err(e) => {
            h2_close_stream(conn);
            raise e;
        },
    };
    match h2_write_bytes(conn, sess.drain()) {
        Result::Ok(_) => 0,
        Result::Err(e) => {
            h2_close_stream(conn);
            raise e;
        },
    };
    let pref = match h2_read_n(conn, 24) {
        Result::Ok(v) => v,
        Result::Err(e) => {
            h2_close_stream(conn);
            raise e;
        },
    };
    match sess.feed(pref) {
        Result::Ok(_) => 0,
        Result::Err(e) => {
            h2_close_stream(conn);
            raise e;
        },
    };
    match h2_write_bytes(conn, sess.drain()) {
        Result::Ok(_) => 0,
        Result::Err(e) => {
            h2_close_stream(conn);
            raise e;
        },
    };
    let answered: Vec<int> = Vec::new();
    let guard = 0;
    while guard < 65536 {
        let f = match h2_read_frame(conn) {
            Result::Ok(v) => v,
            Result::Err(_) => {
                h2_close_stream(conn);
                return ();
            },
        };
        match sess.feed(encode_frame(f)) {
            Result::Ok(_) => 0,
            Result::Err(e) => {
                match h2_write_bytes(conn, sess.drain()) {
                    Result::Ok(_) => 0,
                    Result::Err(_) => 0,
                };
                h2_close_stream(conn);
                raise e;
            },
        };
        let more = 1;
        while more == 1 {
            let opt = match h2_try_read_frame(conn) {
                Result::Ok(v) => v,
                Result::Err(_) => {
                    more = 0;
                    Option::None
                },
            };
            match opt {
                Option::None => {
                    more = 0;
                    0
                },
                Option::Some(f2) => {
                    match sess.feed(encode_frame(f2)) {
                        Result::Ok(_) => 0,
                        Result::Err(e) => {
                            match h2_write_bytes(conn, sess.drain()) {
                                Result::Ok(_) => 0,
                                Result::Err(_) => 0,
                            };
                            h2_close_stream(conn);
                            raise e;
                        },
                    };
                    0
                },
            };
        }
        match h2_dispatch_ready(sess, handler, answered) {
            Result::Ok(_) => 0,
            Result::Err(e) => {
                h2_close_stream(conn);
                raise e;
            },
        };
        match h2_write_bytes(conn, sess.drain()) {
            Result::Ok(_) => 0,
            Result::Err(e) => {
                h2_close_stream(conn);
                raise e;
            },
        };
        if sess.goaway_received() == 1 {
            let settled = h2_streams_settled(sess, answered);
            if settled == 1 {
                h2_close_stream(conn);
                return ();
            }
        }
        guard = guard + 1;
    }
    h2_close_stream(conn);
    return ();
}

fn h2_accept_one(Server srv, Stream conn, HttpHandler handler, int once) -> Result<(), HttpError> {
    let stream = conn;
    if srv.use_tls == 1 {
        stream = match tls_server_enable(conn, new ServerOpts(srv.tls_cert, srv.tls_key, 5000, "", h2_server_alpn())) {
            Result::Ok(s) => s,
            Result::Err(e) => {
                h2_close_stream(conn);
                http_fail_tls(e)?
            },
        };
        let proto = match alpn_protocol(stream) {
            Result::Ok(p) => p,
            Result::Err(e) => {
                h2_close_stream(stream);
                http_fail_tls_unit(e)?;
                ""
            },
        };
        if h2_alpn_is_h2(proto) == 0 {
            if once == 1 {
                return serve_conn_once(srv, stream, handler)?;
            }
            return serve_conn_loop(stream, handler)?;
        }
    }
    return h2_serve_conn(stream, handler)?;
}

/// Accepts one connection and serves every request on it.
///
/// Cleartext connections speak prior-knowledge HTTP/2. With `Server::tls`, ALPN
/// `h2` selects HTTP/2 and anything else (including no ALPN) one HTTP/1.1
/// request through the same handler. Errors are as for `serve_once`.
fn h2_serve_once(Server srv, HttpHandler handler) -> Result<(), HttpError> {
    let listener = match srv.listener {
        Option::None => http_not_bound()?,
        Option::Some(s) => s,
    };
    let conn = match accept_wait(listener) {
        Result::Ok(s) => s,
        Result::Err(e) => http_fail_stream(e)?,
    };
    return h2_accept_one(srv, conn, handler, 1)?;
}

/// Accepts connections one at a time until accepting fails, serving each as
/// `h2_serve_once` does (HTTP/1.1 fallback connections keep alive).
///
/// Errors on one connection only end that connection. Returns
/// `Io(InvalidInput)` when `srv` is not bound; closes and clears the listener
/// when it returns.
fn h2_serve_all(Server srv, HttpHandler handler) -> Result<(), HttpError> {
    let listener = match srv.listener {
        Option::None => http_not_bound()?,
        Option::Some(s) => s,
    };
    let keep = 1;
    while keep == 1 {
        let conn = match accept_wait(listener) {
            Result::Ok(s) => s,
            Result::Err(_) => {
                keep = 0;
                listener
            },
        };
        if keep == 1 {
            match h2_accept_one(srv, conn, handler, 0) {
                Result::Ok(_) => 0,
                Result::Err(_) => 0,
            };
        }
    }
    match io_close(listener) {
        Result::Ok(_) => 0,
        Result::Err(_) => 0,
    };
    srv.listener = Option::None;
    return ();
}

/// The TLS form of `h2_serve_all`: ALPN `h2` is HTTP/2, anything else HTTP/1.1.
///
/// Returns `NotSupported` unless `Server::tls` was called.
fn h2_serve(Server srv, HttpHandler handler) -> Result<(), HttpError> {
    if srv.use_tls == 0 {
        http_err_not_supported()?;
    }
    return h2_serve_all(srv, handler)?;
}
