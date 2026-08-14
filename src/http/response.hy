// HTTP/1.1 response parse and builder.
use io::{to_bytes};
use ascii::{hex_digit, hex_val};
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

fn transfer_encoding_is_chunked(Vec<string> names, Vec<string> values) -> int {
    let i = 0;
    while i < len(names) {
        if header_name_eq_ci(names[i], "Transfer-Encoding") == 1 {
            if header_name_eq_ci(values[i], "chunked") == 1 {
                return 1;
            }
        }
        i = i + 1;
    }
    return 0;
}

fn collect_header_pairs(Vec<byte> header_bytes, Vec<string> names, Vec<string> values) -> Result<int, HttpError> {
    let eol0 = find_crlf(header_bytes, 0);
    if eol0 == 999999 {
        return 0;
    }
    let pos = eol0 + 2;
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
    return 0;
}

fn parse_chunk_size_line(Vec<byte> line) -> Result<int, HttpError> {
    let n = len(line);
    if n == 0 {
        http_err_bad_response()?;
    }
    let v = 0;
    let i = 0;
    let saw = 0;
    while i < n {
        let c = line[i];
        if c == (";" as byte) {
            break;
        }
        if c == (" " as byte) {
            break;
        }
        let d = hex_val(c);
        if d < 0 {
            http_err_bad_response()?;
        }
        v = v * 16 + d;
        saw = 1;
        i = i + 1;
    }
    if saw == 0 {
        http_err_bad_response()?;
    }
    return v;
}

fn int_to_hex(int n) -> string {
    if n == 0 {
        return "0";
    }
    let digits: Vec<byte> = Vec::new();
    let x = n;
    while x > 0 {
        digits.push(hex_digit(x % 16));
        x = x / 16;
    }
    let out: Vec<byte> = Vec::new();
    let i = 0;
    let dn = len(digits);
    while i < dn {
        out.push(digits[dn - 1 - i]);
        i = i + 1;
    }
    return match bytes_to_string(out) {
        Result::Ok(s) => s,
        Result::Err(_) => "0",
    };
}

fn crlf_bytes() -> Vec<byte> {
    let b: Vec<byte> = Vec::new();
    b.push("\r");
    b.push("\n");
    return b;
}

/// Parse chunked `raw` into `out`. Returns byte count consumed, including the last chunk and trailers.
fn decode_chunked_into(Vec<byte> raw, Vec<byte> out) -> Result<int, HttpError> {
    let pos = 0;
    let n = len(raw);
    let crlf = crlf_bytes();
    while pos < n {
        let eol = find_crlf(raw, pos);
        if eol == 999999 {
            http_err_bad_response()?;
        }
        let line = bytes_slice_resp(raw, pos, eol);
        let size = parse_chunk_size_line(line)?;
        pos = eol + 2;
        if size == 0 {
            while pos < n {
                let teol = find_crlf(raw, pos);
                if teol == 999999 {
                    http_err_bad_response()?;
                }
                if teol == pos {
                    return teol + 2;
                }
                pos = teol + 2;
            }
            http_err_bad_response()?;
        }
        if pos + size + 2 > n {
            http_err_bad_response()?;
        }
        let chunk = bytes_slice_resp(raw, pos, pos + size);
        let j = 0;
        while j < size {
            out.push(chunk[j]);
            j = j + 1;
        }
        pos = pos + size;
        if raw[pos] != crlf[0] {
            http_err_bad_response()?;
        }
        if raw[pos + 1] != crlf[1] {
            http_err_bad_response()?;
        }
        pos = pos + 2;
    }
    http_err_bad_response()?;
    return 0;
}

/// Decode a chunked body (no headers). Returns decoded bytes. Truncated input errors.
fn decode_chunked_body(Vec<byte> raw) -> Result<Vec<byte>, HttpError> {
    let out: Vec<byte> = Vec::new();
    decode_chunked_into(raw, out)?;
    return out;
}

/// Encode `body` as one chunk plus a terminating zero chunk.
fn encode_chunked_body(Vec<byte> body) -> Result<Vec<byte>, HttpError> {
    let hex = int_to_hex(len(body));
    let out = to_bytes(hex);
    let crlf = crlf_bytes();
    let i = 0;
    while i < 2 {
        out.push(crlf[i]);
        i = i + 1;
    }
    let j = 0;
    while j < len(body) {
        out.push(body[j]);
        j = j + 1;
    }
    let k = 0;
    while k < 2 {
        out.push(crlf[k]);
        k = k + 1;
    }
    out.push("0");
    let m = 0;
    while m < 2 {
        out.push(crlf[m]);
        m = m + 1;
    }
    let p = 0;
    while p < 2 {
        out.push(crlf[p]);
        p = p + 1;
    }
    return out;
}

/// Exclusive end index of the first HTTP/1.1 message in `raw` (headers + Content-Length or chunked body).
fn http_framed_end(Vec<byte> raw) -> Result<int, HttpError> {
    let sep = find_header_end(raw);
    if sep == 999999 {
        http_err_bad_response()?;
    }
    let header_bytes = bytes_slice_resp(raw, 0, sep);
    let names: Vec<string> = Vec::new();
    let values: Vec<string> = Vec::new();
    collect_header_pairs(header_bytes, names, values)?;
    if transfer_encoding_is_chunked(names, values) == 1 {
        let rest = bytes_slice_resp(raw, sep + 4, len(raw));
        let dump: Vec<byte> = Vec::new();
        let n = decode_chunked_into(rest, dump)?;
        return sep + 4 + n;
    }
    let content_length = content_length_from(names, values)?;
    let end = sep + 4;
    if content_length != 999999 {
        end = sep + 4 + content_length;
        if end > len(raw) {
            http_err_bad_response()?;
        }
    }
    return end;
}

/// Body length from a header block (no trailing CRLFCRLF required).
/// `999999` = no Content-Length (empty body for keep-alive). `999998` = chunked (not framed here).
fn header_block_body_len(Vec<byte> header_bytes) -> Result<int, HttpError> {
    let names: Vec<string> = Vec::new();
    let values: Vec<string> = Vec::new();
    collect_header_pairs(header_bytes, names, values)?;
    if transfer_encoding_is_chunked(names, values) == 1 {
        return 999998;
    }
    return content_length_from(names, values)?;
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
    collect_header_pairs(header_bytes, names, values)?;

    if transfer_encoding_is_chunked(names, values) == 1 {
        let body = decode_chunked_body(rest)?;
        return make_response(status, names, values, body);
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
