// HTTP/1.1 cleartext/TLS server.
use io::{Stream, close as io_close, to_bytes};
use io::net::tcp::{listen, local_addr};
use tls::server::{enable as tls_server_enable, ServerOpts};
use tls::alpn_protocol;
use io::sync::{accept_wait, write_all};

use http::url::{HttpError, Headers, http_err_bad_response, http_err_not_supported, http_fail_stream, http_fail_unit};
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

trait HttpHandler<H> {
    fn handle(H self, IncomingRequest req) -> Response;
}

class Server {
    host: string,
    port: int,
    listener: Option<Stream>,
    tls_cert: string,
    tls_key: string,
    use_tls: int,
}

impl Server {
    pub static fn new() -> Server {
        return new Server("127.0.0.1", 0, Option::None, "", "", 0);
    }

    pub fn bind(string host, int port) -> Result<(), HttpError> {
        let listener = match listen(host, port) {
            Result::Ok(s) => s,
            Result::Err(_) => http_fail_stream()?,
        };
        self.host = host;
        self.port = port;
        self.listener = Option::Some(listener);
        return ();
    }

    pub fn tls(string cert_pem, string key_pem) {
        self.tls_cert = cert_pem;
        self.tls_key = key_pem;
        self.use_tls = 1;
    }

    pub fn bound_port() -> Result<int, HttpError> {
        if match self.listener {
            Option::None => true,
            Option::Some(_) => false,
        } {
            http_fail_unit()?;
            return 0;
        }
        let s = match self.listener {
            Option::Some(v) => v,
            Option::None => http_fail_stream()?,
        };
        let addr = match local_addr(s) {
            Result::Ok(t) => t,
            Result::Err(_) => {
                http_fail_unit()?;
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

/// Accept one TCP connection, optionally wrap TLS, handle one request.
/// `HttpHandler` is existential so accept/read/write run in a non-generic frame
/// (dict-passing `<H: HttpHandler>` does not park WouldBlock).
fn serve_once(Server srv, HttpHandler handler) -> Result<(), HttpError> {
    let listener = match srv.listener {
        Option::None => http_fail_stream()?,
        Option::Some(s) => s,
    };
    let conn = match accept_wait(listener) {
        Result::Ok(s) => s,
        Result::Err(_) => http_fail_stream()?,
    };
    let stream = conn;
    if srv.use_tls == 1 {
        stream = match tls_server_enable(conn, new ServerOpts(srv.tls_cert, srv.tls_key, 0, "", "")) {
            Result::Ok(s) => s,
            Result::Err(_) => http_fail_stream()?,
        };
    }
    return serve_conn_once(srv, stream, handler)?;
}

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

/// Accept one TCP connection and serve HTTP/1.1 until the client closes or sends `Connection: close`.
fn serve_one_client(Server srv, HttpHandler handler) -> Result<(), HttpError> {
    let listener = match srv.listener {
        Option::None => http_fail_stream()?,
        Option::Some(s) => s,
    };
    let conn = match accept_wait(listener) {
        Result::Ok(s) => s,
        Result::Err(_) => http_fail_stream()?,
    };
    let stream = conn;
    if srv.use_tls == 1 {
        stream = match tls_server_enable(conn, new ServerOpts(srv.tls_cert, srv.tls_key, 0, "", "")) {
            Result::Ok(s) => s,
            Result::Err(_) => http_fail_stream()?,
        };
    }
    return serve_conn_loop(stream, handler)?;
}

fn serve(Server srv, HttpHandler handler) -> Result<(), HttpError> {
    let listener = match srv.listener {
        Option::None => http_fail_stream()?,
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
            let stream = conn;
            if srv.use_tls == 1 {
                stream = match tls_server_enable(conn, new ServerOpts(srv.tls_cert, srv.tls_key, 0, "", "")) {
                    Result::Ok(s) => s,
                    Result::Err(_) => {
                        keep = 0;
                        conn
                    },
                };
            }
            if keep == 1 {
                serve_conn_loop(stream, handler)?;
            }
        }
    }
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
    if len(wire) == 0 {
        return ();
    }
    match write_all(s, wire) {
        Result::Ok(_) => 0,
        Result::Err(_) => {
            http_fail_unit()?;
            0
        },
    };
    return ();
}

fn h2_int_has(Vec<int> v, int x) -> int {
    let i = 0;
    while i < len(v) {
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
                    while hi < len(resp.header_names) {
                        fields.add(resp.header_names[hi], resp.header_values[hi]);
                        hi = hi + 1;
                    }
                    let trails = Headers::new();
                    let ti = 0;
                    while ti < len(resp.trailer_names) {
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

/// Speak prior-knowledge HTTP/2 on an already-accepted stream.
/// Each ended stream is dispatched to `handler`.
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
            Result::Err(_) => {
                h2_close_stream(conn);
                http_fail_stream()?
            },
        };
        let proto = match alpn_protocol(stream) {
            Result::Ok(p) => p,
            Result::Err(_) => {
                h2_close_stream(stream);
                http_fail_unit()?;
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

/// Accept one TCP connection. HTTP/2 prior knowledge, or TLS ALPN `h2`.
/// ALPN `http/1.1` (or empty) is served as HTTP/1.1 through the same handler.
fn h2_serve_once(Server srv, HttpHandler handler) -> Result<(), HttpError> {
    let listener = match srv.listener {
        Option::None => http_fail_stream()?,
        Option::Some(s) => s,
    };
    let conn = match accept_wait(listener) {
        Result::Ok(s) => s,
        Result::Err(_) => http_fail_stream()?,
    };
    return h2_accept_one(srv, conn, handler, 1)?;
}

/// Accept connections until the listener fails. Cleartext is prior-knowledge HTTP/2.
/// With `Server.tls`, ALPN `h2` is HTTP/2 and any other selection is HTTP/1.1.
fn h2_serve_all(Server srv, HttpHandler handler) -> Result<(), HttpError> {
    let listener = match srv.listener {
        Option::None => http_fail_stream()?,
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

/// TLS HTTP/2 accept loop. Requires `Server.tls`. ALPN other than `h2` is HTTP/1.1.
fn h2_serve(Server srv, HttpHandler handler) -> Result<(), HttpError> {
    if srv.use_tls == 0 {
        http_err_not_supported()?;
    }
    return h2_serve_all(srv, handler)?;
}
