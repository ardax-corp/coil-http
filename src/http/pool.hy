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

class ConnPool {
    keys: Vec<string>,
    streams: Vec<Stream>,
    max_size: int,
}

impl ConnPool {
    static fn new() -> ConnPool {
        let keys: Vec<string> = Vec::new();
        let streams: Vec<Stream> = Vec::new();
        return new ConnPool(keys, streams, 4);
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

    fn acquire(Url u) -> Result<Stream, HttpError> {
        let key = self.pool_key(u);
        let i = 0;
        let n = len(self.keys);
        while i < n {
            if self.keys[i] == key {
                let s = self.streams[i];
                let last = n - 1;
                if i < last {
                    self.keys[i] = self.keys[last];
                    self.streams[i] = self.streams[last];
                }
                self.keys.pop();
                self.streams.pop();
                return s;
            }
            i = i + 1;
        }
        return self.open_stream(u)?;
    }

    fn release(Url u, Stream s) {
        if len(self.streams) >= self.max_size {
            match close(s) {
                Result::Ok(_) => 0,
                Result::Err(_) => 0,
            };
            return;
        }
        let key = self.pool_key(u);
        self.keys.push(key);
        self.streams.push(s);
    }

    fn discard(Stream s) {
        match close(s) {
            Result::Ok(_) => 0,
            Result::Err(_) => 0,
        };
    }

    fn clear() {
        let i = 0;
        while i < len(self.streams) {
            match close(self.streams[i]) {
                Result::Ok(_) => 0,
                Result::Err(_) => 0,
            };
            i = i + 1;
        }
        self.keys.clear();
        self.streams.clear();
    }
}
