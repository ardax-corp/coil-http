// HTTP/1.1 request builders and client-side Request type.
use io::{from_bytes, to_bytes};
use conv::{int_to_dec};
use http::url::{
    Headers,
    HttpError,
    Url,
    empty_headers,
    http_err_bad_url,
    parse_url,
    url_host,
    url_port,
    url_scheme,
};

/// Outbound HTTP request (method, URL string, headers, body).
class Request {
    method: string,
    url_str: string,
    headers: Headers,
    body: Vec<byte>,
}

impl Request {
    static fn new() -> Request {
        let hs = empty_headers();
        let body: Vec<byte> = Vec::new();
        return new Request("GET", "", hs, body);
    }

    fn method(string m) {
        self.method = m;
    }

    fn url(string u) {
        self.url_str = u;
    }

    fn header(string name, string value) {
        self.headers.add(name, value);
    }

    fn body(Vec<byte> b) {
        self.body = b;
    }

    fn method_val() -> string {
        return self.method;
    }

    fn url_val() -> string {
        return self.url_str;
    }

    fn headers_val() -> Headers {
        return self.headers;
    }

    fn body_val() -> Vec<byte> {
        return self.body;
    }
}

fn request_line_ok(Vec<byte> head) -> int {
    let cr: byte = "\r";
    let lf: byte = "\n";
    let i = 0;
    let n = len(head);
    while i + 1 < n {
        if head[i] == cr {
            if head[i + 1] == lf {
                let needle = to_bytes("HTTP/1.1");
                let j = 0;
                while j + 8 <= i {
                    let ok = true;
                    let k = 0;
                    while k < 8 {
                        if head[j + k] != needle[k] {
                            ok = false;
                        }
                        k = k + 1;
                    }
                    if ok {
                        return 1;
                    }
                    j = j + 1;
                }
                return 0;
            }
        }
        i = i + 1;
    }
    return 0;
}

fn extras_sanitize(string extras) -> Result<string, HttpError> {
    let b = to_bytes(extras);
    let cr: byte = "\r";
    let lf: byte = "\n";
    let colon: byte = ":";
    let line_start = 0;
    let i = 0;
    let n = len(b);
    while i + 1 < n {
        if b[i] == cr {
            if b[i + 1] == lf {
                if i > line_start {
                    let has_colon = 0;
                    let j = line_start;
                    while j < i {
                        if b[j] == colon {
                            has_colon = 1;
                        }
                        j = j + 1;
                    }
                    if has_colon == 0 {
                        http_err_bad_url()?;
                    }
                }
                line_start = i + 2;
                i = i + 2;
            } else {
                i = i + 1;
            }
        } else {
            i = i + 1;
        }
    }
    return match from_bytes(b) {
        Result::Ok(s) => s,
        Result::Err(_) => {
            http_err_bad_url()?;
            ""
        },
    };
}

fn host_header_value(Url u) -> Result<string, HttpError> {
    let host = url_host(u)?;
    let port = url_port(u)?;
    let scheme = url_scheme(u)?;
    if scheme == "http" {
        if port == 80 {
            return host;
        }
    }
    if scheme == "ws" {
        if port == 80 {
            return host;
        }
    }
    if scheme == "https" {
        if port == 443 {
            return host;
        }
    }
    if scheme == "wss" {
        if port == 443 {
            return host;
        }
    }
    return host + ":" + int_to_dec(port);
}

fn body_len_str(int body_len) -> string {
    if body_len == 0 { return "0"; }
    if body_len == 1 { return "1"; }
    if body_len == 2 { return "2"; }
    if body_len == 3 { return "3"; }
    if body_len == 4 { return "4"; }
    if body_len == 5 { return "5"; }
    if body_len == 6 { return "6"; }
    if body_len == 7 { return "7"; }
    if body_len == 8 { return "8"; }
    if body_len == 9 { return "9"; }
    if body_len == 10 { return "10"; }
    if body_len == 11 { return "11"; }
    if body_len == 12 { return "12"; }
    if body_len == 13 { return "13"; }
    if body_len == 14 { return "14"; }
    if body_len == 15 { return "15"; }
    if body_len == 16 { return "16"; }
    if body_len == 17 { return "17"; }
    if body_len == 32 { return "32"; }
    if body_len == 64 { return "64"; }
    if body_len == 128 { return "128"; }
    if body_len == 256 { return "256"; }
    if body_len == 512 { return "512"; }
    if body_len == 1024 { return "1024"; }
    return int_to_dec(body_len);
}

fn concat_bytes(Vec<byte> a, Vec<byte> b) -> Vec<byte> {
    let out: Vec<byte> = Vec::new();
    let i = 0;
    while i < len(a) {
        out.push(a[i]);
        i = i + 1;
    }
    let j = 0;
    while j < len(b) {
        out.push(b[j]);
        j = j + 1;
    }
    return out;
}

fn cl_trailer(int body_len) -> string {
    if body_len == 0 {
        return "0\r\nConnection: close\r\n\r\n";
    } else if body_len == 1 {
        return "1\r\nConnection: close\r\n\r\n";
    } else if body_len == 2 {
        return "2\r\nConnection: close\r\n\r\n";
    } else if body_len == 3 {
        return "3\r\nConnection: close\r\n\r\n";
    } else if body_len == 4 {
        return "4\r\nConnection: close\r\n\r\n";
    } else if body_len == 5 {
        return "5\r\nConnection: close\r\n\r\n";
    } else if body_len == 6 {
        return "6\r\nConnection: close\r\n\r\n";
    } else if body_len == 7 {
        return "7\r\nConnection: close\r\n\r\n";
    } else if body_len == 8 {
        return "8\r\nConnection: close\r\n\r\n";
    } else if body_len == 9 {
        return "9\r\nConnection: close\r\n\r\n";
    } else if body_len == 10 {
        return "10\r\nConnection: close\r\n\r\n";
    } else if body_len == 16 {
        return "16\r\nConnection: close\r\n\r\n";
    } else if body_len == 17 {
        return "17\r\nConnection: close\r\n\r\n";
    } else if body_len == 32 {
        return "32\r\nConnection: close\r\n\r\n";
    } else if body_len == 64 {
        return "64\r\nConnection: close\r\n\r\n";
    } else if body_len == 128 {
        return "128\r\nConnection: close\r\n\r\n";
    } else if body_len == 256 {
        return "256\r\nConnection: close\r\n\r\n";
    } else if body_len == 512 {
        return "512\r\nConnection: close\r\n\r\n";
    } else if body_len == 1024 {
        return "1024\r\nConnection: close\r\n\r\n";
    } else {
        return body_len_str(body_len) + "\r\nConnection: close\r\n\r\n";
    }
}

fn ka_trailer(int body_len) -> string {
    if body_len == 0 {
        return "0\r\nConnection: keep-alive\r\n\r\n";
    } else if body_len == 1 {
        return "1\r\nConnection: keep-alive\r\n\r\n";
    } else if body_len == 2 {
        return "2\r\nConnection: keep-alive\r\n\r\n";
    } else if body_len == 3 {
        return "3\r\nConnection: keep-alive\r\n\r\n";
    } else if body_len == 4 {
        return "4\r\nConnection: keep-alive\r\n\r\n";
    } else if body_len == 5 {
        return "5\r\nConnection: keep-alive\r\n\r\n";
    } else if body_len == 6 {
        return "6\r\nConnection: keep-alive\r\n\r\n";
    } else if body_len == 7 {
        return "7\r\nConnection: keep-alive\r\n\r\n";
    } else if body_len == 8 {
        return "8\r\nConnection: keep-alive\r\n\r\n";
    } else if body_len == 9 {
        return "9\r\nConnection: keep-alive\r\n\r\n";
    } else if body_len == 10 {
        return "10\r\nConnection: keep-alive\r\n\r\n";
    } else if body_len == 16 {
        return "16\r\nConnection: keep-alive\r\n\r\n";
    } else if body_len == 32 {
        return "32\r\nConnection: keep-alive\r\n\r\n";
    } else if body_len == 64 {
        return "64\r\nConnection: keep-alive\r\n\r\n";
    } else {
        return body_len_str(body_len) + "\r\nConnection: keep-alive\r\n\r\n";
    }
}

fn is_reserved_request_header(string name) -> int {
    if name == "Host" { return 1; }
    if name == "host" { return 1; }
    if name == "HOST" { return 1; }
    if name == "Content-Length" { return 1; }
    if name == "content-length" { return 1; }
    if name == "CONTENT-LENGTH" { return 1; }
    if name == "Content-length" { return 1; }
    if name == "Connection" { return 1; }
    if name == "connection" { return 1; }
    if name == "CONNECTION" { return 1; }
    return 0;
}

fn format_extra_headers_str(Vec<string> names, Vec<string> values) -> string {
    let first = 999999;
    let i = 0;
    let n = len(names);
    while i < n {
        if is_reserved_request_header(names[i]) == 0 {
            if first == 999999 {
                first = i;
            }
        }
        i = i + 1;
    }
    if first == 999999 {
        return "__NONE__";
    }
    let acc = names[first] + ": " + values[first] + "\r\n";
    let j = first + 1;
    while j < n {
        if is_reserved_request_header(names[j]) == 0 {
            acc = acc + names[j] + ": " + values[j] + "\r\n";
        }
        j = j + 1;
    }
    return acc;
}

fn format_extra_headers(Headers headers) -> Vec<byte> {
    let s = format_extra_headers_str(headers.names, headers.values);
    if s == "__NONE__" {
        let empty: Vec<byte> = Vec::new();
        return empty;
    }
    return to_bytes(s);
}

fn build_head_prefix(string method, Url u) -> string {
    let host = u.host;
    let port = u.port;
    let scheme = u.scheme;
    let path = u.path;
    let host_hdr = host;
    if scheme == "http" {
        if port != 80 {
            host_hdr = host + ":" + int_to_dec(port);
        }
    } else {
        if scheme == "ws" {
            if port != 80 {
                host_hdr = host + ":" + int_to_dec(port);
            }
        } else {
            if scheme == "https" {
                if port != 443 {
                    host_hdr = host + ":" + int_to_dec(port);
                }
            } else {
                if scheme == "wss" {
                    if port != 443 {
                        host_hdr = host + ":" + int_to_dec(port);
                    }
                } else {
                    host_hdr = host + ":" + int_to_dec(port);
                }
            }
        }
    }
    return method + " " + path + " HTTP/1.1\r\nHost: " + host_hdr + "\r\nContent-Length: ";
}

/// Serialize HTTP/1.1 request line + Host + Content-Length + Connection: close.
fn build_request_head(string method, Url u, Headers headers, int body_len) -> Result<Vec<byte>, HttpError> {
    let prefix = build_head_prefix(method, u);
    let rest = cl_trailer(body_len);
    return concat_bytes(to_bytes(prefix), to_bytes(rest));
}

/// Same as `build_request_head` but emits Connection: keep-alive.
fn build_request_head_keepalive(string method, Url u, Headers headers, int body_len) -> Result<Vec<byte>, HttpError> {
    let prefix = build_head_prefix(method, u);
    let rest = ka_trailer(body_len);
    return concat_bytes(to_bytes(prefix), to_bytes(rest));
}

fn build_request_head_extras(string method, Url u, string extras, int body_len) -> Result<Vec<byte>, HttpError> {
    let host_hdr = host_header_value(u)?;
    let prefix = method + " " + u.path + " HTTP/1.1\r\nHost: " + host_hdr + "\r\n" + extras + "Content-Length: ";
    let rest = cl_trailer(body_len);
    return concat_bytes(to_bytes(prefix), to_bytes(rest));
}

fn build_request_head_extras_keepalive(string method, Url u, string extras, int body_len) -> Result<Vec<byte>, HttpError> {
    let host_hdr = host_header_value(u)?;
    let prefix = method + " " + u.path + " HTTP/1.1\r\nHost: " + host_hdr + "\r\n" + extras + "Content-Length: ";
    let rest = ka_trailer(body_len);
    return concat_bytes(to_bytes(prefix), to_bytes(rest));
}

fn req_parse_url(string s) -> Result<Url, HttpError> {
    return parse_url(s)?;
}

fn req_empty_headers() -> Headers {
    return empty_headers();
}
