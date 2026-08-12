// URL parse, headers, and shared HTTP utilities (byte-scan; no string slice/index).
use io::{Stream, from_bytes, to_bytes};

/// URL parse, response parse, scheme, or I/O failure.
enum HttpError {
    BadUrl,
    BadResponse,
    UnsupportedScheme,
    Io,
    NotSupported,
}

/// Parsed `http`/`https` URL (scheme, host, port, path).
class Url {
    scheme: string,
    host: string,
    port: int,
    path: string,
}

/// Parallel name/value header pairs for requests and responses.
class Headers {
    names: Vec<string>,
    values: Vec<string>,
}

impl Headers {
    /// Empty header list.
    static fn new() -> Headers {
        let names: Vec<string> = Vec::new();
        let values: Vec<string> = Vec::new();
        return new Headers(names, values);
    }

    /// Append a header name/value pair.
    fn add(string name, string value) {
        self.names.push(name);
        self.values.push(value);
    }

    /// Number of header pairs.
    fn count() -> int {
        return len(self.names);
    }

    /// Header name at index `i`.
    fn name_at(int i) -> string {
        return self.names[i];
    }

    /// Header value at index `i`.
    fn value_at(int i) -> string {
        return self.values[i];
    }
}

impl Url {
    fn scheme_val() -> string {
        return self.scheme;
    }

    fn host_val() -> string {
        return self.host;
    }

    fn port_val() -> int {
        return self.port;
    }

    fn path_val() -> string {
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
    return len(h.names);
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
        if i < len(src) {
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

/// Find `needle` in `hay`; returns index or 999999 if missing.
fn find_bytes(Vec<byte> hay, Vec<byte> needle) -> int {
    let hn = len(hay);
    let nn = len(needle);
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

fn http_err_bad_response() -> Result<(), HttpError> {
    raise HttpError::BadResponse;
}

fn bytes_have_crlf(Vec<byte> b) -> int {
    let i = 0;
    let cr: byte = "\r";
    let lf: byte = "\n";
    while i < len(b) {
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
    let n = len(names);
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

fn http_err_io() -> Result<(), HttpError> {
    raise HttpError::Io;
}

fn http_fail_stream() -> Result<Stream, HttpError> {
    raise HttpError::Io;
}

fn http_fail_bytes() -> Result<Vec<byte>, HttpError> {
    raise HttpError::Io;
}

fn http_fail_unit() -> Result<(), HttpError> {
    raise HttpError::Io;
}

/// Parse `http://` or `https://` URL string.
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
    if rest_start > len(b) {
        http_err_bad_url()?;
    }

    let slash: byte = "/";
    let qmark: byte = "?";
    let colon: byte = ":";

    let i = rest_start;
    let host_end = len(b);
    let path_start = len(b);
    let port_start = 0;
    let has_port = 0;
    let found_path = 0;

    while i < len(b) {
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
            host_end = len(b);
        }
        path_start = len(b);
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
    if scheme == "http" {
        port = 80;
    }
    if has_port == 1 {
        let port_end = path_start;
        if found_path == 0 {
            port_end = len(b);
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
            let path_b = bytes_slice(b, path_start, len(b));
            if bytes_have_crlf(path_b) == 1 {
                http_err_bad_url()?;
            }
            path = bytes_to_string(path_b)?;
        } else {
            let path_b = bytes_slice(b, path_start, len(b));
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
    http_err_unsupported_scheme()?;
    return new Url(scheme, host, port, path);
}

fn header_name_eq_ci(string a, string b) -> int {
    let ab = to_bytes(a);
    let bb = to_bytes(b);
    if len(ab) != len(bb) {
        return 0;
    }
    let i = 0;
    while i < len(ab) {
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
