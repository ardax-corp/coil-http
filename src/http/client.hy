// HTTP/1.1 client with optional connection pooling.
use io::sync::{write_all};

use http::url::{
    Headers,
    HttpError,
    Url,
    empty_headers,
    headers_have_crlf,
    http_err_bad_url,
    http_fail_unit,
    parse_url,
    http_err_invalid_header,
};
use http::request::{
    Request,
    build_request_head,
    build_request_head_extras,
    build_request_head_extras_keepalive,
    build_request_head_keepalive,
    concat_bytes,
    extras_sanitize,
    format_extra_headers_str,
    request_line_ok,
};
use http::response::{
    Response,
    parse_response,
    response_body_len,
    response_status,
};
use http::pool::{ConnPool};
use http::conn::{read_http_message};
use http::h2_session::{H2ClientSlot, h2_slot_close, h2_slot_empty, h2_slot_exchange};

/// An HTTP client for `http://` and `https://` URLs.
///
/// `get`, `post` and `send` speak HTTP/1.1. By default they send
/// `Connection: keep-alive` and return the connection to a per-client pool
/// (`ConnPool`, up to 4 idle connections) when the response allows it, so later
/// requests to the same scheme, host and port reuse the socket. `no_pool`
/// switches to one connection per request.
///
/// `h2_get`, `h2_post` and `h2_send` speak HTTP/2 on one connection per client,
/// kept separately from the HTTP/1.1 pool. Cleartext URLs use prior knowledge (the
/// connection preface is sent straight away); `https://` offers ALPN
/// `h2,http/1.1` and falls back to HTTP/1.1 on the same connection when the
/// server does not pick `h2`.
///
/// HTTPS certificates are verified against the bundled webpki roots through coil-tls. The
/// program needs `--allow-net`, and for HTTPS also `--allow-attach` and the
/// `libtls` grants (see the package README). There are no redirects, cookies or
/// timeouts; a non-2xx status is an ordinary `Ok` response.
///
/// Call `close` when done: dropping the client closes its sockets only when the
/// garbage collector runs.
///
/// # Examples
///
/// ```no_run
/// use http::client::Client;
/// use string::{from_bytes, to_bytes};
///
/// fn main() {
///     let c = Client::new();
///     let r = match c.get("https://example.com/") {
///         Result::Ok(r) => r,
///         Result::Err(e) => panic show(e),
///     };
///     if r.status != 200 {
///         panic "unexpected status";
///     }
///     let page = from_bytes(r.body);
///
///     let posted = c.post("http://127.0.0.1:8080/echo", to_bytes("hello"));
///     c.close();
/// }
/// ```
class Client {
    pool: ConnPool,
    use_pool: int,
    h2: H2ClientSlot,
}

impl Client {
    /// A client with HTTP/1.1 connection pooling on and no open connections.
    pub static fn new() -> Client {
        let p = ConnPool::new();
        return new Client(p, 1, h2_slot_empty());
    }

    /// Turns pooling off: later requests send `Connection: close` and close their
    /// connection after the response.
    pub fn no_pool() {
        self.use_pool = 0;
    }

    /// Closes every pooled HTTP/1.1 connection and the HTTP/2 session.
    ///
    /// The client stays usable; the next request opens a new connection.
    pub fn close() {
        self.pool.clear();
        h2_slot_close(self.h2);
    }

    fn drop() {
        self.close();
        self.use_pool = self.use_pool;
    }

    /// Sends an already serialized request head plus `body` to `u` and reads one
    /// response.
    ///
    /// Low-level: `head` must be a complete HTTP/1.1 head (see `build_request_head`).
    /// Prefer `send`. The connection goes back to the pool when pooling is on and the
    /// response was framed; on any error it is closed.
    pub fn request_send(Vec<byte> head, Url u, Vec<byte> body) -> Result<Response, HttpError> {
        let msg = concat_bytes(head, body);
        let c = self.pool.acquire(u)?;
        match write_all(c.stream(), msg) {
            Result::Ok(_) => 0,
            Result::Err(e) => {
                self.pool.discard(c);
                http_fail_unit(e)?;
                0
            },
        };
        let raw = match read_http_message(c) {
            Result::Ok(b) => b,
            Result::Err(e) => {
                self.pool.discard(c);
                return Result::Err(e);
            },
        };
        let resp = match parse_response(raw) {
            Result::Ok(r) => r,
            Result::Err(e) => {
                self.pool.discard(c);
                raise e;
            },
        };
        if self.use_pool == 1 {
            if c.can_reuse() == 1 {
                self.pool.release(u, c);
            } else {
                self.pool.discard(c);
            }
        } else {
            self.pool.discard(c);
        }
        return resp;
    }

    /// Sends `req` over HTTP/1.1 and returns the response.
    ///
    /// Returns `BadUrl` when the URL or method does not parse or holds CR / LF,
    /// `InvalidHeader` for CR / LF in a header field, `UnsupportedScheme` for anything
    /// but `http` and `https`, `Io` / `Tls` when connecting or the socket fails, and
    /// `Protocol` when the response is malformed.
    ///
    /// # Examples
    ///
    /// ```no_run
    /// use http::client::Client;
    /// use http::request::Request;
    /// use string::to_bytes;
    ///
    /// fn main() {
    ///     let c = Client::new();
    ///     let req = Request::new();
    ///     req.method("PUT");
    ///     req.url("http://127.0.0.1:8080/items/1");
    ///     req.header("Content-Type", "application/json");
    ///     req.body(to_bytes("{}"));
    ///     match c.send(req) {
    ///         Result::Ok(r) => r.status,
    ///         Result::Err(e) => panic show(e),
    ///     };
    /// }
    /// ```
    pub fn send(Request req) -> Result<Response, HttpError> {
        let method = req.method_val();
        let url = req.url_val();
        let headers = req.headers_val();
        let body = req.body_val();
        let u = parse_url(url)?;
        let bl = body.len();
        let n = headers.names.len();
        let keep = self.use_pool;
        if n > 0 {
            if headers_have_crlf(headers.names, headers.values) == 1 {
                http_err_invalid_header()?;
            }
            let extras = format_extra_headers_str(headers.names, headers.values);
            if extras != "__NONE__" {
                let extras = extras_sanitize(extras)?;
                if keep == 1 {
                    let head = build_request_head_extras_keepalive(method, u, extras, bl)?;
                    if request_line_ok(head) == 0 {
                        http_err_bad_url()?;
                    }
                    return self.request_send(head, u, body)?;
                }
                let head = build_request_head_extras(method, u, extras, bl)?;
                if request_line_ok(head) == 0 {
                    http_err_bad_url()?;
                }
                return self.request_send(head, u, body)?;
            }
        }
        if keep == 1 {
            let head = build_request_head_keepalive(method, u, headers, bl)?;
            if request_line_ok(head) == 0 {
                http_err_bad_url()?;
            }
            return self.request_send(head, u, body)?;
        }
        let head = build_request_head(method, u, headers, bl)?;
        if request_line_ok(head) == 0 {
            http_err_bad_url()?;
        }
        return self.request_send(head, u, body)?;
    }

    /// Sends `GET url` over HTTP/1.1. Errors are as for `send`.
    ///
    /// # Examples
    ///
    /// ```no_run
    /// use http::client::Client;
    /// use http::url::HttpError;
    /// use io::IoError;
    ///
    /// fn main() {
    ///     let c = Client::new();
    ///     match c.get("http://example.com/") {
    ///         Result::Ok(r) => r.status,
    ///         Result::Err(HttpError::Io(IoError::TimedOut)) => 0,
    ///         Result::Err(e) => panic show(e),
    ///     };
    /// }
    /// ```
    pub fn get(string url) -> Result<Response, HttpError> {
        let req = Request::new();
        req.method("GET");
        req.url(url);
        return self.send(req)?;
    }

    /// Sends `POST url` with `body` over HTTP/1.1. Errors are as for `send`.
    pub fn post(string url, Vec<byte> body) -> Result<Response, HttpError> {
        let req = Request::new();
        req.method("POST");
        req.url(url);
        req.body(body);
        return self.send(req)?;
    }

    /// Sends `GET url` over HTTP/2 (HTTP/1.1 when an `https://` server does not
    /// select `h2`).
    ///
    /// The first call dials the origin; later calls to the same origin open a new
    /// stream on that connection, and a call to another origin replaces it. Response
    /// header fields and trailers are on the returned `Response`.
    ///
    /// # Examples
    ///
    /// ```no_run
    /// use http::client::Client;
    /// use http::response::header_get;
    ///
    /// fn main() {
    ///     let c = Client::new();
    ///     let a = c.h2_get("https://example.com/a");
    ///     let b = c.h2_get("https://example.com/b");
    ///     c.close();
    /// }
    /// ```
    pub fn h2_get(string url) -> Result<Response, HttpError> {
        let extra = Headers::new();
        let body: Vec<byte> = Vec::new();
        return h2_slot_exchange(self.h2, url, "GET", extra, body)?;
    }

    /// Sends `POST url` with `body` over HTTP/2, like `h2_get`.
    pub fn h2_post(string url, Vec<byte> body) -> Result<Response, HttpError> {
        let extra = Headers::new();
        return h2_slot_exchange(self.h2, url, "POST", extra, body)?;
    }

    /// Sends `req` over HTTP/2, like `h2_get`, with its method, header fields and body.
    pub fn h2_send(Request req) -> Result<Response, HttpError> {
        return h2_slot_exchange(self.h2, req.url_val(), req.method_val(), req.headers_val(), req.body_val())?;
    }
}

fn status_code(Response r) -> Result<int, HttpError> {
    return response_status(r)?;
}

fn body_len(Response r) -> Result<int, HttpError> {
    return response_body_len(r)?;
}
