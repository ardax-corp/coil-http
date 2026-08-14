// TCP/TLS connection pool for HTTP/1.1 keep-alive (M4).
use io::{Stream, close};
use io::net::tcp::connect as tcp_connect;
use io::net::tls::client::enable as tls_enable;
use conv::{int_to_dec};
use http::url::{
    HttpError,
    Url,
    http_err_unsupported_scheme,
    http_fail_stream,
    url_host,
    url_port,
    url_scheme,
};
use http::conn::{HttpConn, close_conn};

class ConnPool {
    keys: Vec<string>,
    conns: Vec<HttpConn>,
    max_size: int,
}

impl ConnPool {
    static fn new() -> ConnPool {
        let keys: Vec<string> = Vec::new();
        let conns: Vec<HttpConn> = Vec::new();
        return new ConnPool(keys, conns, 4);
    }

    fn max(int n) {
        self.max_size = n;
    }

    fn pool_key(Url u) -> string {
        let scheme = u.scheme;
        let host = u.host;
        let port = u.port;
        return scheme + "://" + host + ":" + int_to_dec(port);
    }

    fn open_stream(Url u) -> Result<Stream, HttpError> {
        let scheme = url_scheme(u)?;
        let host = url_host(u)?;
        let port = url_port(u)?;
        if scheme == "http" {
            return match tcp_connect(host, port) {
                Result::Ok(s) => s,
                Result::Err(_) => http_fail_stream()?,
            };
        }
        if scheme == "https" {
            let s = match tcp_connect(host, port) {
                Result::Ok(s) => s,
                Result::Err(_) => http_fail_stream()?,
            };
            return match tls_enable(s, host, { verify: true, ca_pem: Option::None, ca_path: Option::None, timeout_ms: 0, alpn: "" }) {
                Result::Ok(s) => s,
                Result::Err(_) => {
                    match close(s) {
                        Result::Ok(_) => 0,
                        Result::Err(_) => 0,
                    };
                    http_fail_stream()?
                },
            };
        }
        http_err_unsupported_scheme()?;
        return http_fail_stream()?;
    }

    fn acquire(Url u) -> Result<HttpConn, HttpError> {
        let key = self.pool_key(u);
        let i = 0;
        let n = len(self.keys);
        while i < n {
            if self.keys[i] == key {
                let c = self.conns[i];
                let last = n - 1;
                if i < last {
                    self.keys[i] = self.keys[last];
                    self.conns[i] = self.conns[last];
                }
                self.keys.pop();
                self.conns.pop();
                return c;
            }
            i = i + 1;
        }
        let s = self.open_stream(u)?;
        return HttpConn::wrap(s);
    }

    fn release(Url u, HttpConn c) {
        if len(self.conns) >= self.max_size {
            close_conn(c);
            return;
        }
        let key = self.pool_key(u);
        self.keys.push(key);
        self.conns.push(c);
    }

    fn discard(HttpConn c) {
        close_conn(c);
    }

    fn clear() {
        let i = 0;
        while i < len(self.conns) {
            close_conn(self.conns[i]);
            i = i + 1;
        }
        self.keys.clear();
        self.conns.clear();
    }
}
