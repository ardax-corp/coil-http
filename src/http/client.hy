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

class Client {
    pool: ConnPool,
    use_pool: int,
    h2: H2ClientSlot,
}

impl Client {
    pub static fn new() -> Client {
        let p = ConnPool::new();
        return new Client(p, 1, h2_slot_empty());
    }

    pub fn no_pool() {
        self.use_pool = 0;
    }

    pub fn close() {
        self.pool.clear();
        h2_slot_close(self.h2);
    }

    fn drop() {
        self.close();
        self.use_pool = self.use_pool;
    }

    pub fn request_send(Vec<byte> head, Url u, Vec<byte> body) -> Result<Response, HttpError> {
        let msg = concat_bytes(head, body);
        let c = self.pool.acquire(u)?;
        match write_all(c.stream(), msg) {
            Result::Ok(_) => 0,
            Result::Err(_) => {
                self.pool.discard(c);
                http_fail_unit()?;
                0
            },
        };
        let raw = match read_http_message(c) {
            Result::Ok(b) => b,
            Result::Err(_) => {
                self.pool.discard(c);
                http_fail_unit()?;
                Vec::new()
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

    pub fn send(Request req) -> Result<Response, HttpError> {
        let method = req.method_val();
        let url = req.url_val();
        let headers = req.headers_val();
        let body = req.body_val();
        let u = parse_url(url)?;
        let bl = len(body);
        let n = len(headers.names);
        let keep = self.use_pool;
        if n > 0 {
            if headers_have_crlf(headers.names, headers.values) == 1 {
                http_err_bad_url()?;
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

    pub fn get(string url) -> Result<Response, HttpError> {
        let req = Request::new();
        req.method("GET");
        req.url(url);
        return self.send(req)?;
    }

    pub fn post(string url, Vec<byte> body) -> Result<Response, HttpError> {
        let req = Request::new();
        req.method("POST");
        req.url(url);
        req.body(body);
        return self.send(req)?;
    }

    /// HTTP/2 GET. Cleartext sends the connection preface. HTTPS uses ALPN.
    /// Repeated calls on this client reuse one connection with new stream ids.
    pub fn h2_get(string url) -> Result<Response, HttpError> {
        let extra = Headers::new();
        let body: Vec<byte> = Vec::new();
        return h2_slot_exchange(self.h2, url, "GET", extra, body)?;
    }

    /// HTTP/2 POST with a request body.
    pub fn h2_post(string url, Vec<byte> body) -> Result<Response, HttpError> {
        let extra = Headers::new();
        return h2_slot_exchange(self.h2, url, "POST", extra, body)?;
    }

    /// HTTP/2 request using the same builder fields as `send`.
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
