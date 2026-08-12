// HTTP/1.1 response parse and builder.
use io::{to_bytes};
use http::url::{
    HttpError,
    Headers,
    bytes_to_string,
    header_name_eq_ci,
    http_err_bad_response,
};

/// Parsed HTTP response (status, headers, body).
class Response {
    status: int,
    header_names: Vec<string>,
    header_values: Vec<string>,
    body: Vec<byte>,
}

impl Response {
    /// 200 OK with empty body and headers.
    static fn ok() -> Response {
        let names: Vec<string> = Vec::new();
        let values: Vec<string> = Vec::new();
        let body: Vec<byte> = Vec::new();
        return new Response(200, names, values, body);
    }

    fn status(int code) {
        self.status = code;
    }

    fn header(string name, string value) {
        self.header_names.push(name);
        self.header_values.push(value);
    }

    fn body(Vec<byte> b) {
        self.body = b;
    }
}

fn make_response(int status, Vec<string> names, Vec<string> values, Vec<byte> body) -> Response {
    return new Response(status, names, values, body);
}

fn response_status(Response r) -> Result<int, HttpError> {
    return r.status;
}

fn response_body_len(Response r) -> Result<int, HttpError> {
    return len(r.body);
}

fn header_count(Response r) -> int {
    return len(r.header_names);
}

fn header_name_at_resp(Response r, int i) -> string {
    return r.header_names[i];
}

fn header_get(Response r, string name) -> string {
    let i = 0;
    let n = len(r.header_names);
    while i < n {
        if r.header_names[i] == name {
            return r.header_values[i];
        }
        i = i + 1;
    }
    return "";
}

fn find_header_end(Vec<byte> buf) -> int {
    let cr: byte = "\r";
    let lf: byte = "\n";
    let i = 0;
    let n = len(buf);
    while i + 3 < n {
        if buf[i] == cr {
            if buf[i + 1] == lf {
                if buf[i + 2] == cr {
                    if buf[i + 3] == lf {
                        return i;
                    }
                }
            }
        }
        i = i + 1;
    }
    return 999999;
}

fn bytes_slice_resp(Vec<byte> src, int start, int end) -> Vec<byte> {
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

fn find_crlf(Vec<byte> buf, int from) -> int {
    let cr: byte = "\r";
    let lf: byte = "\n";
    let i = from;
    while i + 1 < len(buf) {
        if buf[i] == cr {
            if buf[i + 1] == lf {
                return i;
            }
        }
        i = i + 1;
    }
    return 999999;
}

fn parse_status_code(Vec<byte> line) -> Result<int, HttpError> {
    let sp: byte = " ";
    let i = 0;
    let n = len(line);
    while i < n {
        if line[i] == sp {
            i = i + 1;
            break;
        }
        i = i + 1;
    }
    let start = i;
    while i < n {
        if line[i] == sp {
            break;
        }
        i = i + 1;
    }
    if i <= start {
        http_err_bad_response()?;
    }
    let code = 0;
    let j = start;
    while j < i {
        code = code * 10 + ((line[j] as int) - (("0" as byte) as int));
        j = j + 1;
    }
    return code;
}

fn parse_int_bytes(Vec<byte> b) -> Result<int, HttpError> {
    let n = len(b);
    if n == 0 {
        http_err_bad_response()?;
    }
    let v = 0;
    let i = 0;
    while i < n {
        v = v * 10 + ((b[i] as int) - (("0" as byte) as int));
        i = i + 1;
    }
    return v;
}

fn find_byte(Vec<byte> line, byte needle) -> int {
    let k = 0;
    while k < len(line) {
        if line[k] == needle {
            return k;
        }
        k = k + 1;
    }
    return 999999;
}

fn parse_status_line(Vec<byte> header_bytes) -> Result<int, HttpError> {
    let eol = find_crlf(header_bytes, 0);
    let line_end = len(header_bytes);
    if eol != 999999 {
        line_end = eol;
    }
    let line = bytes_slice_resp(header_bytes, 0, line_end);
    return parse_status_code(line)?;
}

fn append_header_line(Vec<string> names, Vec<string> values, Vec<byte> line) -> Result<int, HttpError> {
    let colon: byte = ":";
    let sp: byte = " ";
    let cpos = find_byte(line, colon);
    if cpos == 999999 {
        http_err_bad_response()?;
    }
    let name_b = bytes_slice_resp(line, 0, cpos);
    let val_start = cpos + 1;
    if val_start < len(line) {
        if line[val_start] == sp {
            val_start = val_start + 1;
        }
    }
    let val_b = bytes_slice_resp(line, val_start, len(line));
    let name = bytes_to_string(name_b)?;
    let value = bytes_to_string(val_b)?;
    names.push(name);
    values.push(value);
    return 0;
}

fn content_length_from(Vec<string> names, Vec<string> values) -> Result<int, HttpError> {
    let i = 0;
    while i < len(names) {
        if header_name_eq_ci(names[i], "Content-Length") == 1 {
            return parse_int_bytes(to_bytes(values[i]))?;
        }
        i = i + 1;
    }
    return 999999;
}

/// Parse raw HTTP/1.1 response bytes into `Response`.
fn parse_response(Vec<byte> raw) -> Result<Response, HttpError> {
    let sep = find_header_end(raw);
    if sep == 999999 {
        http_err_bad_response()?;
    }
    let header_bytes = bytes_slice_resp(raw, 0, sep);
    let rest = bytes_slice_resp(raw, sep + 4, len(raw));

    let status = parse_status_line(header_bytes)?;

    let names: Vec<string> = Vec::new();
    let values: Vec<string> = Vec::new();
    let eol0 = find_crlf(header_bytes, 0);
    let pos = 0;
    if eol0 != 999999 {
        pos = eol0 + 2;
    }
    let n = len(header_bytes);
    while pos < n {
        let eol = find_crlf(header_bytes, pos);
        let line_end = n;
        if eol != 999999 {
            line_end = eol;
        }
        if line_end > pos {
            let line = bytes_slice_resp(header_bytes, pos, line_end);
            append_header_line(names, values, line)?;
        }
        if eol == 999999 {
            pos = n;
        } else {
            pos = eol + 2;
        }
    }

    let content_length = content_length_from(names, values)?;
    let body = rest;
    if content_length != 999999 {
        if content_length > len(rest) {
            http_err_bad_response()?;
        }
        if content_length < len(rest) {
            body = bytes_slice_resp(rest, 0, content_length);
        }
    }
    return make_response(status, names, values, body);
}
