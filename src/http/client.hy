// HTTP/1.1 client with optional connection pooling.
use io::{Stream, close};
use io::sync::{read_to_end, write_all};

use http::url::{
    Headers,
    HttpError,
    Url,
    empty_headers,
    headers_have_crlf,
    http_err_bad_url,
    http_fail_bytes,
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

class Client {
    pool: ConnPool,
    use_pool: int,
}

impl Client {
    static fn new() -> Client {
        let p = ConnPool::new();
        return new Client(p, 1);
    }

    fn no_pool() {
        self.use_pool = 0;
    }

    fn request_send(Vec<byte> head, Url u, Vec<byte> body) -> Result<Response, HttpError> {
        let msg = concat_bytes(head, body);
        let s = self.pool.acquire(u)?;
        match write_all(s, msg) {
            Result::Ok(_) => 0,
            Result::Err(_) => {
                self.pool.discard(s);
                http_fail_unit()?;
                0
            },
        };
        let raw = match read_to_end(s) {
            Result::Ok(b) => b,
            Result::Err(_) => {
                self.pool.discard(s);
                http_fail_bytes()?
            },
        };
        if self.use_pool == 1 {
            self.pool.release(u, s);
        } else {
            match close(s) {
                Result::Ok(_) => 0,
                Result::Err(_) => 0,
            };
        }
        return parse_response(raw)?;
    }

    fn send(Request req) -> Result<Response, HttpError> {
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

    fn get(string url) -> Result<Response, HttpError> {
        let req = Request::new();
        req.method("GET");
        req.url(url);
        return self.send(req)?;
    }

    fn post(string url, Vec<byte> body) -> Result<Response, HttpError> {
        let req = Request::new();
        req.method("POST");
        req.url(url);
        req.body(body);
        return self.send(req)?;
    }
}

fn status_code(Response r) -> Result<int, HttpError> {
    return response_status(r)?;
}

fn body_len(Response r) -> Result<int, HttpError> {
    return response_body_len(r)?;
}
