// URL parse, headers, and shared HTTP utilities (byte-scan; no string slice/index).
use io::{Stream, IoError};
use string::{from_bytes, to_bytes};
use tls::error::{TlsError};

/// An HTTP failure, returned by every fallible call in this package.
///
/// Socket and TLS failures keep the lower layer's error (`Io(IoError)`,
/// `Tls(TlsError)`), so a caller can tell a timeout from a refused connection or a
/// bad certificate. The enum derives `Show` and `Eq`.
///
/// # Examples
///
/// ```
/// # use tests::assert;
/// use http::url::{HttpError, parse_url};
///
/// let bad = match parse_url("ftp://example.com/") {
///     Result::Ok(_) => false,
///     Result::Err(HttpError::UnsupportedScheme) => true,
///     Result::Err(_) => false,
/// };
/// assert!(bad);
/// ```
#[derive(Show, Eq)]
enum HttpError {
    /// The URL does not parse, or its host or path holds CR / LF.
    BadUrl,
    /// A request header name or value holds CR / LF, or a header line has no `:`.
    InvalidHeader,
    /// The URL scheme is not `http`, `https`, `ws` or `wss`.
    UnsupportedScheme,
    /// The feature is not implemented (HTTP/3).
    NotSupported,
    /// The peer broke HTTP/1.1, HTTP/2 or WebSocket framing.
    Protocol,
    /// The socket failed.
    Io(IoError),
    /// The TLS layer failed.
    Tls(TlsError),
}

/// A parsed `http`, `https`, `ws` or `wss` URL.
///
/// Built by `parse_url`. The query string, if any, stays on `path`
/// (`/search?q=coil`); there is no separate fragment or user-info part.
///
/// # Examples
///
/// ```
/// # use tests::assert;
/// use http::url::parse_url;
///
/// let u = match parse_url("https://example.com:8443/a?b=1") {
///     Result::Ok(u) => u,
///     Result::Err(e) => panic show(e),
/// };
/// assert!(u.scheme == "https");
/// assert!(u.host == "example.com");
/// assert!(u.port == 8443);
/// assert!(u.path == "/a?b=1");
/// ```
class Url {
    /// Scheme: `http`, `https`, `ws` or `wss`.
    pub scheme: string,
    /// Host name or IPv4 address, without the port.
    pub host: string,
    /// Port: the explicit one, or 80 for `http`/`ws` and 443 for `https`/`wss`.
    pub port: int,
    /// Path and query (`/a?b=1`); `/` when the URL has none.
    pub path: string,
}

/// An ordered list of header fields, kept as parallel name and value vectors.
///
/// Names keep the case they were added or received with, and duplicates are
/// allowed. Used for request headers (`Request::header`), parsed request headers
/// (`IncomingRequest.headers`) and HTTP/2 header blocks.
///
/// # Examples
///
/// ```
/// # use tests::assert;
/// use http::url::Headers;
///
/// let h = Headers::new();
/// h.add("Accept", "text/plain");
/// h.add("X-Trace", "abc");
/// assert!(h.count() == 2);
/// assert!(h.name_at(1) == "X-Trace");
/// assert!(h.value_at(1) == "abc");
/// ```
class Headers {
    /// Field names, in insertion order.
    pub names: Vec<string>,
    /// Field values; `values[i]` belongs to `names[i]`.
    pub values: Vec<string>,
}

impl Headers {
    /// An empty header list.
    pub static fn new() -> Headers {
        let names: Vec<string> = Vec::new();
        let values: Vec<string> = Vec::new();
        return new Headers(names, values);
    }

    /// Appends the field `name: value`. An existing field with the same name is kept.
    pub fn add(string name, string value) {
        self.names.push(name);
        self.values.push(value);
    }

    /// The number of fields.
    pub fn count() -> int {
        return self.names.len();
    }

    /// The name of field `i`. Panics if `i` is out of range.
    pub fn name_at(int i) -> string {
        return self.names[i];
    }

    /// The value of field `i`. Panics if `i` is out of range.
    pub fn value_at(int i) -> string {
        return self.values[i];
    }
}

impl Url {
    /// The scheme (same as the `scheme` field).
    pub fn scheme_val() -> string {
        return self.scheme;
    }

    /// The host (same as the `host` field).
    pub fn host_val() -> string {
        return self.host;
    }

    /// The port (same as the `port` field).
    pub fn port_val() -> int {
        return self.port;
    }

    /// The path and query (same as the `path` field).
    pub fn path_val() -> string {
        return self.path;
    }
}

fn empty_headers() -> Headers {
    return Headers::new();
}

fn header_add(Headers h, string name, string value) {
    h.add(name, value);
    return h;
}

fn url_scheme(Url u) -> Result<string, HttpError> {
    return u.scheme;
}

fn url_host(Url u) -> Result<string, HttpError> {
    return u.host;
}

fn url_port(Url u) -> Result<int, HttpError> {
    return u.port;
}

fn url_path(Url u) -> Result<string, HttpError> {
    return u.path;
}

fn headers_count(Headers h) -> Result<int, HttpError> {
    return h.names.len();
}

fn header_name_at(Headers h, int i) -> Result<string, HttpError> {
    return h.names[i];
}

fn header_value_at(Headers h, int i) -> Result<string, HttpError> {
    return h.values[i];
}

fn bytes_slice(Vec<byte> src, int start, int end) -> Vec<byte> {
    let out: Vec<byte> = Vec::new();
    let i = start;
    while i < end {
        if i < src.len() {
            out.push(src[i]);
        }
        i = i + 1;
    }
    return out;
}

fn bytes_to_string(Vec<byte> b) -> Result<string, HttpError> {
    return match from_bytes(b) {
        Result::Ok(s) => s,
        Result::Err(_) => raise HttpError::BadUrl,
    };
}

// Find `needle` in `hay`; returns index or 999999 if missing.
fn find_bytes(Vec<byte> hay, Vec<byte> needle) -> int {
    let hn = hay.len();
    let nn = needle.len();
    if nn == 0 {
        return 0;
    }
    if nn > hn {
        return 999999;
    }
    let i = 0;
    while i + nn <= hn {
        let ok = true;
        let j = 0;
        while j < nn {
            if hay[i + j] != needle[j] {
                ok = false;
            }
            j = j + 1;
        }
        if ok {
            return i;
        }
        i = i + 1;
    }
    return 999999;
}

fn parse_port_digits(Vec<byte> b, int start, int end) -> int {
    let n = 0;
    let i = start;
    let zero: byte = "0";
    let nine: byte = "9";
    if start >= end {
        return 999999;
    }
    while i < end {
        let c = b[i];
        if c < zero {
            return 999999;
        }
        if c > nine {
            return 999999;
        }
        n = n * 10 + ((c as int) - (("0" as byte) as int));
        i = i + 1;
    }
    return n;
}

fn http_err_bad_url() -> Result<(), HttpError> {
    raise HttpError::BadUrl;
}

fn http_err_invalid_header() -> Result<(), HttpError> {
    raise HttpError::InvalidHeader;
}

fn http_err_protocol() -> Result<(), HttpError> {
    raise HttpError::Protocol;
}

fn bytes_have_crlf(Vec<byte> b) -> int {
    let i = 0;
    let cr: byte = "\r";
    let lf: byte = "\n";
    while i < b.len() {
        if b[i] == cr {
            return 1;
        }
        if b[i] == lf {
            return 1;
        }
        i = i + 1;
    }
    return 0;
}

fn has_crlf(string s) -> int {
    return bytes_have_crlf(to_bytes(s));
}

fn str_reject_crlf(string s) -> Result<string, HttpError> {
    let b = to_bytes(s);
    if bytes_have_crlf(b) == 1 {
        http_err_bad_url()?;
    }
    return match from_bytes(b) {
        Result::Ok(s2) => s2,
        Result::Err(_) => {
            http_err_bad_url()?;
            ""
        },
    };
}

fn headers_have_crlf(Vec<string> names, Vec<string> values) -> int {
    let i = 0;
    let n = names.len();
    while i < n {
        if has_crlf(names[i]) == 1 {
            return 1;
        }
        if has_crlf(values[i]) == 1 {
            return 1;
        }
        i = i + 1;
    }
    return 0;
}

fn http_err_unsupported_scheme() -> Result<(), HttpError> {
    raise HttpError::UnsupportedScheme;
}

fn http_err_not_supported() -> Result<(), HttpError> {
    raise HttpError::NotSupported;
}

fn http_err_io(IoError e) -> Result<(), HttpError> {
    raise HttpError::Io(e);
}

fn http_fail_stream(IoError e) -> Result<Stream, HttpError> {
    raise HttpError::Io(e);
}

fn http_fail_bytes(IoError e) -> Result<Vec<byte>, HttpError> {
    raise HttpError::Io(e);
}

fn http_fail_unit(IoError e) -> Result<(), HttpError> {
    raise HttpError::Io(e);
}

fn http_fail_tls(TlsError e) -> Result<Stream, HttpError> {
    raise HttpError::Tls(e);
}

fn http_fail_tls_unit(TlsError e) -> Result<(), HttpError> {
    raise HttpError::Tls(e);
}

// No listener: `Server.bind` was not called.
fn http_not_bound() -> Result<Stream, HttpError> {
    raise HttpError::Io(IoError::InvalidInput);
}

/// Parses an `http://`, `https://`, `ws://` or `wss://` URL.
///
/// The port defaults to 80 (`http`, `ws`) or 443 (`https`, `wss`) and the path to
/// `/`. A query string with no path (`http://host?q=1`) becomes the path `?q=1`.
///
/// Returns `BadUrl` when there is no `://`, the host is empty, the port is not
/// decimal digits, or the host or path holds CR / LF; `UnsupportedScheme` for any
/// other scheme. IPv6 literals (`[::1]`) are not supported.
///
/// # Examples
///
/// ```
/// # use tests::assert;
/// use http::url::parse_url;
///
/// let u = match parse_url("http://localhost:8080/health") {
///     Result::Ok(u) => u,
///     Result::Err(e) => panic show(e),
/// };
/// assert!(u.host == "localhost");
/// assert!(u.port == 8080);
/// assert!(u.path == "/health");
///
/// let plain = match parse_url("https://example.com") {
///     Result::Ok(u) => u,
///     Result::Err(e) => panic show(e),
/// };
/// assert!(plain.port == 443);
/// assert!(plain.path == "/");
/// ```
fn parse_url(string s) -> Result<Url, HttpError> {
    let b = to_bytes(s);
    let sep = to_bytes("://");
    let sep_at = find_bytes(b, sep);
    if sep_at == 999999 {
        http_err_bad_url()?;
    }
    let scheme_b = bytes_slice(b, 0, sep_at);
    let scheme = bytes_to_string(scheme_b)?;
    let rest_start = sep_at + 3;
    if rest_start > b.len() {
        http_err_bad_url()?;
    }

    let slash: byte = "/";
    let qmark: byte = "?";
    let colon: byte = ":";

    let i = rest_start;
    let host_end = b.len();
    let path_start = b.len();
    let port_start = 0;
    let has_port = 0;
    let found_path = 0;

    while i < b.len() {
        let c = b[i];
        if found_path == 0 {
            if c == colon {
                if has_port == 0 {
                    host_end = i;
                    port_start = i + 1;
                    has_port = 1;
                }
            }
            if c == slash {
                if has_port == 0 {
                    host_end = i;
                }
                path_start = i;
                found_path = 1;
            }
            if c == qmark {
                if has_port == 0 {
                    host_end = i;
                }
                path_start = i;
                found_path = 1;
            }
        }
        i = i + 1;
    }

    if found_path == 0 {
        if has_port == 1 {
            host_end = port_start - 1;
        } else {
            host_end = b.len();
        }
        path_start = b.len();
    } else {
        if has_port == 1 {
            if port_start >= path_start {
                has_port = 0;
            }
        }
    }

    if host_end <= rest_start {
        http_err_bad_url()?;
    }
    let host_b = bytes_slice(b, rest_start, host_end);
    if bytes_have_crlf(host_b) == 1 {
        http_err_bad_url()?;
    }
    let host = bytes_to_string(host_b)?;

    let port = 80;
    if scheme == "https" {
        port = 443;
    }
    if scheme == "wss" {
        port = 443;
    }
    if scheme == "http" {
        port = 80;
    }
    if scheme == "ws" {
        port = 80;
    }
    if has_port == 1 {
        let port_end = path_start;
        if found_path == 0 {
            port_end = b.len();
        }
        let parsed = parse_port_digits(b, port_start, port_end);
        if parsed == 999999 {
            http_err_bad_url()?;
        }
        port = parsed;
    }

    let path = "/";
    if found_path == 1 {
        if b[path_start] == qmark {
            let path_b = bytes_slice(b, path_start, b.len());
            if bytes_have_crlf(path_b) == 1 {
                http_err_bad_url()?;
            }
            path = bytes_to_string(path_b)?;
        } else {
            let path_b = bytes_slice(b, path_start, b.len());
            if bytes_have_crlf(path_b) == 1 {
                http_err_bad_url()?;
            }
            path = bytes_to_string(path_b)?;
        }
    }

    if scheme == "http" {
        return new Url(scheme, host, port, path);
    }
    if scheme == "https" {
        return new Url(scheme, host, port, path);
    }
    if scheme == "ws" {
        return new Url(scheme, host, port, path);
    }
    if scheme == "wss" {
        return new Url(scheme, host, port, path);
    }
    http_err_unsupported_scheme()?;
    return new Url(scheme, host, port, path);
}

fn header_name_eq_ci(string a, string b) -> int {
    let ab = to_bytes(a);
    let bb = to_bytes(b);
    if ab.len() != bb.len() {
        return 0;
    }
    let i = 0;
    while i < ab.len() {
        let x = ab[i] as int;
        let y = bb[i] as int;
        if x >= 65 {
            if x <= 90 {
                x = x + 32;
            }
        }
        if y >= 65 {
            if y <= 90 {
                y = y + 32;
            }
        }
        if x != y {
            return 0;
        }
        i = i + 1;
    }
    return 1;
}
