// HTTP/1.1 response parse and builder.
use string::{to_bytes};
use ascii::{hex_digit, hex_val};
use http::url::{
    HttpError,
    Headers,
    bytes_to_string,
    header_name_eq_ci,
    http_err_protocol,
};

/// An HTTP response: status, header fields, body and HTTP/2 trailing fields.
///
/// The client returns one for every request (`Client::get`, `send`, `h2_get`, ...).
/// A server's `HttpHandler::handle` builds one with `Response::ok` and the setter
/// methods. Header fields are kept in order with the case they were received or
/// added with; look one up with `header_get`.
///
/// # Examples
///
/// Building a response in a handler:
///
/// ```
/// # use tests::assert;
/// use http::response::{Response, header_get};
/// use string::to_bytes;
///
/// let r = Response::ok();
/// r.status(201);
/// r.header("Content-Type", "text/plain");
/// r.body(to_bytes("created"));
/// assert!(r.status == 201);
/// assert!(header_get(r, "Content-Type") == "text/plain");
/// assert!(r.body.len() == 7);
/// ```
///
/// Reading one the client returned:
///
/// ```no_run
/// use http::client::Client;
/// use http::response::header_get;
/// use string::from_bytes;
///
/// fn main() {
///     let c = Client::new();
///     let r = match c.get("http://example.com/") {
///         Result::Ok(r) => r,
///         Result::Err(e) => panic show(e),
///     };
///     let kind = header_get(r, "Content-Type");
///     let text = from_bytes(r.body);
/// }
/// ```
class Response {
    /// Status code, such as 200 or 404.
    pub status: int,
    /// Header field names, in order.
    pub header_names: Vec<string>,
    /// Header field values; `header_values[i]` belongs to `header_names[i]`.
    pub header_values: Vec<string>,
    /// Body bytes, already de-chunked.
    pub body: Vec<byte>,
    /// Trailing field names (HTTP/2 only; empty on HTTP/1.1).
    pub trailer_names: Vec<string>,
    /// Trailing field values; `trailer_values[i]` belongs to `trailer_names[i]`.
    pub trailer_values: Vec<string>,
}

impl Response {
    /// A `200` response with no header fields and an empty body.
    pub static fn ok() -> Response {
        let names: Vec<string> = Vec::new();
        let values: Vec<string> = Vec::new();
        let body: Vec<byte> = Vec::new();
        let trailer_names: Vec<string> = Vec::new();
        let trailer_values: Vec<string> = Vec::new();
        return new Response(200, names, values, body, trailer_names, trailer_values);
    }

    /// Sets the status code.
    ///
    /// The HTTP/1.1 encoder writes a reason phrase for a few common codes and `OK`
    /// for the rest; clients go by the code.
    pub fn status(int code) {
        self.status = code;
    }

    /// Appends a header field.
    ///
    /// The server writes `Content-Length` and `Connection` itself, so do not add
    /// those. Add
    /// `Transfer-Encoding: chunked` to send the body chunked on HTTP/1.1.
    pub fn header(string name, string value) {
        self.header_names.push(name);
        self.header_values.push(value);
    }

    /// Sets the body.
    pub fn body(Vec<byte> b) {
        self.body = b;
    }

    /// Appends a trailing field, sent after the body on HTTP/2. HTTP/1.1 does not send trailers.
    pub fn trailer(string name, string value) {
        self.trailer_names.push(name);
        self.trailer_values.push(value);
    }
}

fn make_response(int status, Vec<string> names, Vec<string> values, Vec<byte> body) -> Response {
    let trailer_names: Vec<string> = Vec::new();
    let trailer_values: Vec<string> = Vec::new();
    return new Response(status, names, values, body, trailer_names, trailer_values);
}

fn response_status(Response r) -> Result<int, HttpError> {
    return r.status;
}

fn response_body_len(Response r) -> Result<int, HttpError> {
    return r.body.len();
}

fn header_count(Response r) -> int {
    return r.header_names.len();
}

fn header_name_at_resp(Response r, int i) -> string {
    return r.header_names[i];
}

/// The value of the first header field of `r` named exactly `name`, or `""`.
///
/// The name comparison is case-sensitive: use the case the peer sent.
///
/// # Examples
///
/// ```
/// # use tests::assert;
/// use http::response::{header_get, parse_response};
/// use string::to_bytes;
///
/// let raw = to_bytes("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\n\r\nhi");
/// let r = match parse_response(raw) {
///     Result::Ok(r) => r,
///     Result::Err(e) => panic show(e),
/// };
/// assert!(header_get(r, "Content-Type") == "text/plain");
/// assert!(header_get(r, "X-Missing") == "");
/// ```
fn header_get(Response r, string name) -> string {
    let i = 0;
    let n = r.header_names.len();
    while i < n {
        if r.header_names[i] == name {
            return r.header_values[i];
        }
        i = i + 1;
    }
    return "";
}

/// The value of the first trailing field of `r` named exactly `name`, or `""`. Trailers arrive on HTTP/2 only.
fn trailer_get(Response r, string name) -> string {
    let i = 0;
    let n = r.trailer_names.len();
    while i < n {
        if r.trailer_names[i] == name {
            return r.trailer_values[i];
        }
        i = i + 1;
    }
    return "";
}

fn find_header_end(Vec<byte> buf) -> int {
    let cr: byte = "\r";
    let lf: byte = "\n";
    let i = 0;
    let n = buf.len();
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
        if i < src.len() {
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
    while i + 1 < buf.len() {
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
    let n = line.len();
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
        http_err_protocol()?;
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
    let n = b.len();
    if n == 0 {
        http_err_protocol()?;
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
    while k < line.len() {
        if line[k] == needle {
            return k;
        }
        k = k + 1;
    }
    return 999999;
}

fn parse_status_line(Vec<byte> header_bytes) -> Result<int, HttpError> {
    let eol = find_crlf(header_bytes, 0);
    let line_end = header_bytes.len();
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
        http_err_protocol()?;
    }
    let name_b = bytes_slice_resp(line, 0, cpos);
    let val_start = cpos + 1;
    if val_start < line.len() {
        if line[val_start] == sp {
            val_start = val_start + 1;
        }
    }
    let val_b = bytes_slice_resp(line, val_start, line.len());
    let name = bytes_to_string(name_b)?;
    let value = bytes_to_string(val_b)?;
    names.push(name);
    values.push(value);
    return 0;
}

fn content_length_from(Vec<string> names, Vec<string> values) -> Result<int, HttpError> {
    let i = 0;
    while i < names.len() {
        if header_name_eq_ci(names[i], "Content-Length") == 1 {
            return parse_int_bytes(to_bytes(values[i]))?;
        }
        i = i + 1;
    }
    return 999999;
}

fn transfer_encoding_is_chunked(Vec<string> names, Vec<string> values) -> int {
    let i = 0;
    while i < names.len() {
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
    let n = header_bytes.len();
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
    let n = line.len();
    if n == 0 {
        http_err_protocol()?;
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
        let d = hex_val(c) ?? -1;
        if d < 0 {
            http_err_protocol()?;
        }
        v = v * 16 + d;
        saw = 1;
        i = i + 1;
    }
    if saw == 0 {
        http_err_protocol()?;
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
    let dn = digits.len();
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

// Parse chunked `raw` into `out`. Returns byte count consumed, including the last chunk and trailers.
fn decode_chunked_into(Vec<byte> raw, Vec<byte> out) -> Result<int, HttpError> {
    let pos = 0;
    let n = raw.len();
    let crlf = crlf_bytes();
    while pos < n {
        let eol = find_crlf(raw, pos);
        if eol == 999999 {
            http_err_protocol()?;
        }
        let line = bytes_slice_resp(raw, pos, eol);
        let size = parse_chunk_size_line(line)?;
        pos = eol + 2;
        if size == 0 {
            while pos < n {
                let teol = find_crlf(raw, pos);
                if teol == 999999 {
                    http_err_protocol()?;
                }
                if teol == pos {
                    return teol + 2;
                }
                pos = teol + 2;
            }
            http_err_protocol()?;
        }
        if pos + size + 2 > n {
            http_err_protocol()?;
        }
        let chunk = bytes_slice_resp(raw, pos, pos + size);
        let j = 0;
        while j < size {
            out.push(chunk[j]);
            j = j + 1;
        }
        pos = pos + size;
        if raw[pos] != crlf[0] {
            http_err_protocol()?;
        }
        if raw[pos + 1] != crlf[1] {
            http_err_protocol()?;
        }
        pos = pos + 2;
    }
    http_err_protocol()?;
    return 0;
}

/// Decodes an HTTP/1.1 chunked body (no head) into its bytes.
///
/// Chunk extensions and trailer fields are skipped. Returns `Protocol` when the
/// input is truncated or a chunk size is not hex.
fn decode_chunked_body(Vec<byte> raw) -> Result<Vec<byte>, HttpError> {
    let out: Vec<byte> = Vec::new();
    decode_chunked_into(raw, out)?;
    return out;
}

/// Encodes `body` as one chunk followed by the terminating zero-size chunk.
fn encode_chunked_body(Vec<byte> body) -> Result<Vec<byte>, HttpError> {
    let hex = int_to_hex(body.len());
    let out = to_bytes(hex);
    let crlf = crlf_bytes();
    let i = 0;
    while i < 2 {
        out.push(crlf[i]);
        i = i + 1;
    }
    let j = 0;
    while j < body.len() {
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

/// The end offset (exclusive) of the first complete HTTP/1.1 message in `raw`.
///
/// The message is framed by `Transfer-Encoding: chunked`, by `Content-Length`, or
/// ends at the blank line when it has neither. Bytes after the offset belong to
/// the next message. Returns `Protocol` when `raw` holds no complete message.
fn http_framed_end(Vec<byte> raw) -> Result<int, HttpError> {
    let sep = find_header_end(raw);
    if sep == 999999 {
        http_err_protocol()?;
    }
    let header_bytes = bytes_slice_resp(raw, 0, sep);
    let names: Vec<string> = Vec::new();
    let values: Vec<string> = Vec::new();
    collect_header_pairs(header_bytes, names, values)?;
    if transfer_encoding_is_chunked(names, values) == 1 {
        let rest = bytes_slice_resp(raw, sep + 4, raw.len());
        let dump: Vec<byte> = Vec::new();
        let n = decode_chunked_into(rest, dump)?;
        return sep + 4 + n;
    }
    let content_length = content_length_from(names, values)?;
    let end = sep + 4;
    if content_length != 999999 {
        end = sep + 4 + content_length;
        if end > raw.len() {
            http_err_protocol()?;
        }
    }
    return end;
}

// Body length from a header block (no trailing CRLFCRLF required).
// `999999` = no Content-Length (empty body for keep-alive). `999998` = chunked (not framed here).
fn header_block_body_len(Vec<byte> header_bytes) -> Result<int, HttpError> {
    let names: Vec<string> = Vec::new();
    let values: Vec<string> = Vec::new();
    collect_header_pairs(header_bytes, names, values)?;
    if transfer_encoding_is_chunked(names, values) == 1 {
        return 999998;
    }
    return content_length_from(names, values)?;
}

/// Parses a complete HTTP/1.1 response (head and body) into a `Response`.
///
/// A chunked body is decoded; a `Content-Length` body is cut to that length, and
/// without either the rest of `raw` is the body. Returns `Protocol` when there is
/// no blank line after the head, a header line has no `:`, the status code is
/// missing, or the body is shorter than `Content-Length`.
///
/// # Examples
///
/// ```
/// # use tests::assert;
/// use http::response::parse_response;
/// use string::to_bytes;
///
/// let raw = to_bytes("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nhi\r\n0\r\n\r\n");
/// let r = match parse_response(raw) {
///     Result::Ok(r) => r,
///     Result::Err(e) => panic show(e),
/// };
/// assert!(r.status == 200);
/// assert!(r.body.len() == 2);
/// ```
fn parse_response(Vec<byte> raw) -> Result<Response, HttpError> {
    let sep = find_header_end(raw);
    if sep == 999999 {
        http_err_protocol()?;
    }
    let header_bytes = bytes_slice_resp(raw, 0, sep);
    let rest = bytes_slice_resp(raw, sep + 4, raw.len());

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
        if content_length > rest.len() {
            http_err_protocol()?;
        }
        if content_length < rest.len() {
            body = bytes_slice_resp(rest, 0, content_length);
        }
    }
    return make_response(status, names, values, body);
}
