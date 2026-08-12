// HTTP/1.1 cleartext/TLS server.
use io::{Stream, close};
use io::net::tcp::{listen, local_addr};
use io::net::tls::server::enable as tls_server_enable;
use io::sync::{accept_wait, write_all};

use http::url::{HttpError, Headers, http_fail_stream, http_fail_unit};
use http::h1::{IncomingRequest, encode_response, incoming_wants_close, parse_request};
use http::response::{Response};
use http::conn::{read_request_bytes};

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
}

fn serve_conn_once<H: HttpHandler>(Server srv, Stream s, H handler) -> Result<(), HttpError> {
    let raw = read_request_bytes(s)?;
    let req = parse_request(raw)?;
    let resp = handle(handler, req);
    let wire = encode_response(resp);
    match write_all(s, wire) {
        Result::Ok(_) => 0,
        Result::Err(_) => {
            http_fail_unit()?;
            0
        },
    };
    match close(s) {
        Result::Ok(_) => 0,
        Result::Err(_) => 0,
    };
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
    let keep_going = 1;
    while keep_going == 1 {
        let raw_ok = 0;
        let raw = match read_request_bytes(s) {
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
                match write_all(s, wire) {
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
    match close(s) {
        Result::Ok(_) => 0,
        Result::Err(_) => 0,
    };
    return ();
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
    match close(listener) {
        Result::Ok(_) => 0,
        Result::Err(_) => 0,
    };
    return ();
}
