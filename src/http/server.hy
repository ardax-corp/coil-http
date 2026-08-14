// HTTP/1.1 cleartext/TLS server.
use io::{Stream, close as io_close, to_bytes};
use io::net::tcp::{listen, local_addr};
use io::net::tls::server::enable as tls_server_enable;
use io::sync::{accept_wait, write_all};

use http::url::{HttpError, Headers, http_err_bad_response, http_err_not_supported, http_fail_stream, http_fail_unit};
use http::h1::{IncomingRequest, encode_response, encode_response_keepalive, incoming_wants_close, parse_request};
use http::response::{Response};
use http::conn::{HttpConn, close_conn, read_http_message};
use http::h2::{
    data_frame,
    empty_settings_frame,
    encode_frame,
    h2_alpn_is_h2,
    h2_read_frame,
    h2_read_n,
    h2_server_alpn,
    h2_write_frame,
    headers_frame,
};
use http::h2_session::{H2Session};
use io::net::tls::{alpn_protocol};

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
    static fn new() -> Server {
        return new Server("127.0.0.1", 0, Option::None, "", "", 0);
    }

    fn bind(string host, int port) -> Result<(), HttpError> {
        let listener = match listen(host, port) {
            Result::Ok(s) => s,
            Result::Err(_) => http_fail_stream()?,
        };
        self.host = host;
        self.port = port;
        self.listener = Option::Some(listener);
        return ();
    }

    fn tls(string cert_pem, string key_pem) {
        self.tls_cert = cert_pem;
        self.tls_key = key_pem;
        self.use_tls = 1;
    }

    fn bound_port() -> Result<int, HttpError> {
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

fn serve_conn_once<H: HttpHandler>(Server srv, Stream s, H handler) -> Result<(), HttpError> {
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

fn serve_once<H: HttpHandler>(Server srv, H handler) -> Result<(), HttpError> {
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
        stream = match tls_server_enable(conn, { cert_pem: srv.tls_cert, key_pem: srv.tls_key, timeout_ms: 0, client_ca_pem: "", alpn: "" }) {
            Result::Ok(s) => s,
            Result::Err(_) => http_fail_stream()?,
        };
    }
    return serve_conn_once(srv, stream, handler)?;
}

fn serve_conn_loop<H: HttpHandler>(Stream s, H handler) -> Result<(), HttpError> {
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
fn serve_one_client<H: HttpHandler>(Server srv, H handler) -> Result<(), HttpError> {
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
        stream = match tls_server_enable(conn, { cert_pem: srv.tls_cert, key_pem: srv.tls_key, timeout_ms: 0, client_ca_pem: "", alpn: "" }) {
            Result::Ok(s) => s,
            Result::Err(_) => http_fail_stream()?,
        };
    }
    return serve_conn_loop(stream, handler)?;
}

fn serve<H: HttpHandler>(Server srv, H handler) -> Result<(), HttpError> {
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
                stream = match tls_server_enable(conn, { cert_pem: srv.tls_cert, key_pem: srv.tls_key, timeout_ms: 0, client_ca_pem: "", alpn: "" }) {
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

/// Speak prior-knowledge HTTP/2 on an already-accepted (and optionally TLS) stream.
fn h2_serve_conn(Stream conn) -> Result<(), HttpError> {
    match h2_write_frame(conn, empty_settings_frame()) {
        Result::Ok(_) => 0,
        Result::Err(e) => {
            h2_close_stream(conn);
            raise e;
        },
    };
    let sess = H2Session::new();
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
    let done = 0;
    let guard = 0;
    while done == 0 {
        if guard >= 64 {
            h2_close_stream(conn);
            http_err_bad_response()?;
        }
        let f = match h2_read_frame(conn) {
            Result::Ok(v) => v,
            Result::Err(e) => {
                h2_close_stream(conn);
                raise e;
            },
        };
        match sess.feed(encode_frame(f)) {
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
        if sess.stream_count() > 0 {
            let ended = match sess.stream_ended(1) {
                Result::Ok(v) => v,
                Result::Err(e) => {
                    h2_close_stream(conn);
                    raise e;
                },
            };
            if ended == 1 {
                done = 1;
            }
        }
        guard = guard + 1;
    }
    let rh = Headers::new();
    rh.add(":status", "200");
    match h2_write_frame(conn, headers_frame(1, rh, 0)) {
        Result::Ok(_) => 0,
        Result::Err(e) => {
            h2_close_stream(conn);
            raise e;
        },
    };
    match h2_write_frame(conn, data_frame(1, to_bytes("ok"), 1)) {
        Result::Ok(_) => 0,
        Result::Err(e) => {
            h2_close_stream(conn);
            raise e;
        },
    };
    // Drain inbound SETTINGS ACK so close does not RST unread bytes.
    match h2_read_frame(conn) {
        Result::Ok(_) => 0,
        Result::Err(_) => 0,
    };
    h2_close_stream(conn);
    return ();
}

/// Accept one TCP connection; TLS+ALPN `h2` when `Server.tls` was set.
fn h2_serve_once(Server srv) -> Result<(), HttpError> {
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
        stream = match tls_server_enable(conn, { cert_pem: srv.tls_cert, key_pem: srv.tls_key, timeout_ms: 0, client_ca_pem: "", alpn: h2_server_alpn() }) {
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
            h2_close_stream(stream);
            http_err_bad_response()?;
        }
    }
    return h2_serve_conn(stream)?;
}

/// TLS HTTP/2 server one-shot: requires `Server.tls`; ALPN `h2` then prior-knowledge GET.
fn h2_serve(Server srv) -> Result<(), HttpError> {
    if srv.use_tls == 0 {
        http_err_not_supported()?;
    }
    return h2_serve_once(srv)?;
}
