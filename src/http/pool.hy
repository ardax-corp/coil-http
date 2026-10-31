// TCP/TLS connection pool for HTTP/1.1 keep-alive (M4).
use io::{Stream, close};
use io::net::tcp::connect as tcp_connect;
use tls::client::{enable as tls_enable, ClientOpts};
use conv::{int_to_dec};
use http::url::{
    HttpError,
    Url,
    http_err_unsupported_scheme,
    http_fail_stream,
    url_host,
    url_port,
    url_scheme,
    http_fail_tls,
};
use http::conn::{HttpConn, close_conn};

/// Idle HTTP/1.1 connections, keyed by scheme, host and port, for keep-alive.
///
/// Every `Client` owns one; most programs never touch it directly. `acquire`
/// hands out an idle connection for the URL's origin or dials a new one (TLS for
/// `https`), and `release` puts it back once a response was read in full. The
/// pool holds at most `max` idle connections (4 by default); a connection
/// released into a full pool is closed.
///
/// # Examples
///
/// ```no_run
/// use http::pool::ConnPool;
/// use http::url::parse_url;
///
/// fn main() {
///     let pool = ConnPool::new();
///     pool.max(8);
///     let u = match parse_url("http://127.0.0.1:8080/") {
///         Result::Ok(u) => u,
///         Result::Err(e) => panic show(e),
///     };
///     let c = match pool.acquire(u) {
///         Result::Ok(c) => c,
///         Result::Err(e) => panic show(e),
///     };
///     // ... write a request on c.stream(), read the response ...
///     pool.release(u, c);
///     pool.clear();
/// }
/// ```
class ConnPool {
    keys: Vec<string>,
    conns: Vec<HttpConn>,
    max_size: int,
}

impl ConnPool {
    /// An empty pool that keeps up to 4 idle connections.
    pub static fn new() -> ConnPool {
        let keys: Vec<string> = Vec::new();
        let conns: Vec<HttpConn> = Vec::new();
        return new ConnPool(keys, conns, 4);
    }

    /// Sets the most idle connections the pool keeps.
    pub fn max(int n) {
        self.max_size = n;
    }

    /// The pool key for `u`: `scheme://host:port`.
    pub fn pool_key(Url u) -> string {
        let scheme = u.scheme;
        let host = u.host;
        let port = u.port;
        return scheme + "://" + host + ":" + int_to_dec(port);
    }

    /// Dials a new connection to `u`'s origin, bypassing the pool.
    ///
    /// `https` URLs get a verified TLS session. Returns `UnsupportedScheme` for
    /// anything but `http` and `https`, `Io` when connecting fails and `Tls` when
    /// the handshake fails.
    pub fn open_stream(Url u) -> Result<Stream, HttpError> {
        let scheme = url_scheme(u)?;
        let host = url_host(u)?;
        let port = url_port(u)?;
        if scheme == "http" {
            return match tcp_connect(host, port) {
                Result::Ok(s) => s,
                Result::Err(e) => http_fail_stream(e)?,
            };
        }
        if scheme == "https" {
            let s = match tcp_connect(host, port) {
                Result::Ok(s) => s,
                Result::Err(e) => http_fail_stream(e)?,
            };
            return match tls_enable(s, host, new ClientOpts(true, Option::None, Option::None, 0, "")) {
                Result::Ok(s) => s,
                Result::Err(e) => {
                    match close(s) {
                        Result::Ok(_) => 0,
                        Result::Err(_) => 0,
                    };
                    http_fail_tls(e)?
                },
            };
        }
        raise HttpError::UnsupportedScheme;
    }

    /// An idle connection for `u`'s origin, or a new one from `open_stream`.
    pub fn acquire(Url u) -> Result<HttpConn, HttpError> {
        let key = self.pool_key(u);
        let i = 0;
        let n = self.keys.len();
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

    /// Returns `c` to the pool under `u`'s origin, or closes it when the pool is full.
    pub fn release(Url u, HttpConn c) {
        if self.conns.len() >= self.max_size {
            close_conn(c);
            return;
        }
        let key = self.pool_key(u);
        self.keys.push(key);
        self.conns.push(c);
    }

    /// Closes `c` without pooling it.
    pub fn discard(HttpConn c) {
        close_conn(c);
    }

    /// Closes and forgets every idle connection.
    pub fn clear() {
        let i = 0;
        while i < self.conns.len() {
            close_conn(self.conns[i]);
            i = i + 1;
        }
        self.keys.clear();
        self.conns.clear();
    }

    fn drop() {
        self.clear();
        self.max_size = self.max_size;
    }
}
