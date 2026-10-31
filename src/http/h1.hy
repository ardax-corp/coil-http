// HTTP/1.1 wire helpers shared by client and server.
use string::{to_bytes};
use conv::{int_to_dec};
use http::url::{
    Headers,
    HttpError,
    bytes_to_string,
    find_bytes,
    header_name_eq_ci,
    http_err_protocol,
};
use http::request::{concat_bytes};
use http::response::{Response, find_crlf, find_header_end, bytes_slice_resp, parse_int_bytes, decode_chunked_body as resp_decode_chunked, encode_chunked_body as resp_encode_chunked, transfer_encoding_is_chunked};

/// A request received by the server, as passed to `HttpHandler::handle`.
///
/// On HTTP/1.1 it comes from `parse_request`. On HTTP/2 the pseudo-headers are
/// mapped: `method` and `path` come from `:method` and `:path`, `:authority`
/// becomes a `Host` field, and `version` is `HTTP/2`.
///
/// # Examples
///
/// ```
/// # use tests::assert;
/// use http::h1::parse_request;
/// use string::to_bytes;
///
/// let raw = to_bytes("POST /items?x=1 HTTP/1.1\r\nHost: example.com\r\nContent-Length: 3\r\n\r\nabc");
/// let req = match parse_request(raw) {
///     Result::Ok(r) => r,
///     Result::Err(e) => panic show(e),
/// };
/// assert!(req.method_val() == "POST");
/// assert!(req.path_val() == "/items?x=1");
/// assert!(req.version == "HTTP/1.1");
/// assert!(req.headers_val().value_at(0) == "example.com");
/// assert!(req.body_val().len() == 3);
/// ```
class IncomingRequest {
    /// Request method as sent (`GET`, `POST`, ...).
    pub method: string,
    /// Request target: path and query, as sent.
    pub path: string,
    /// Protocol version: `HTTP/1.1` (as sent) or `HTTP/2`.
    pub version: string,
    /// Header fields in the order received.
    pub headers: Headers,
    /// Body bytes, already de-chunked.
    pub body: Vec<byte>,
}

impl IncomingRequest {
    /// The method.
    pub fn method_val() -> string {
        return self.method;
    }

    /// The path and query.
    pub fn path_val() -> string {
        return self.path;
    }

    /// The header fields.
    pub fn headers_val() -> Headers {
        return self.headers;
    }

    /// The body.
    pub fn body_val() -> Vec<byte> {
        return self.body;
    }
}

fn incoming_content_length(Headers h) -> Result<int, HttpError> {
    let i = 0;
    let n = h.names.len();
    while i < n {
        if header_name_eq_ci(h.names[i], "Content-Length") == 1 {
            return parse_int_bytes(to_bytes(h.values[i]))?;
        }
        i = i + 1;
    }
    return 999999;
}

fn connection_is_close(Headers h) -> int {
    let i = 0;
    let n = h.names.len();
    while i < n {
        if header_name_eq_ci(h.names[i], "Connection") == 1 {
            if h.values[i] == "close" {
                return 1;
            }
            if h.values[i] == "Close" {
                return 1;
            }
            if h.values[i] == "CLOSE" {
                return 1;
            }
        }
        i = i + 1;
    }
    return 0;
}

/// Parses a complete HTTP/1.1 request (head and body) into an `IncomingRequest`.
///
/// A chunked body is decoded and a `Content-Length` body is cut to that length.
/// Header lines without `:` are skipped. Returns `Protocol` when the head has no
/// blank line, the request line is not `METHOD target version`, or the body is
/// shorter than `Content-Length`.
fn parse_request(Vec<byte> raw) -> Result<IncomingRequest, HttpError> {
    let sep = find_header_end(raw);
    if sep == 999999 {
        http_err_protocol()?;
    }
    let header_bytes = bytes_slice_resp(raw, 0, sep);
    let rest = bytes_slice_resp(raw, sep + 4, raw.len());

    let eol0 = find_crlf(header_bytes, 0);
    if eol0 == 999999 {
        http_err_protocol()?;
    }
    let line = bytes_slice_resp(header_bytes, 0, eol0);
    let sp: byte = " ";
    let ln = line.len();
    let mi = 0;
    let m_end = 999999;
    while mi < ln {
        if line[mi] == sp {
            m_end = mi;
            break;
        }
        mi = mi + 1;
    }
    if m_end == 999999 {
        http_err_protocol()?;
    }
    let method = bytes_to_string(bytes_slice_resp(line, 0, m_end))?;

    let p_start = m_end + 1;
    let p_end = 999999;
    let pj = p_start;
    while pj < ln {
        if line[pj] == sp {
            p_end = pj;
            break;
        }
        pj = pj + 1;
    }
    if p_end == 999999 {
        http_err_protocol()?;
    }
    let path = bytes_to_string(bytes_slice_resp(line, p_start, p_end))?;

    let v_start = p_end + 1;
    let version = bytes_to_string(bytes_slice_resp(line, v_start, ln))?;

    let headers = Headers::new();
    let pos = eol0 + 2;
    let n = header_bytes.len();
    while pos < n {
        let eol = find_crlf(header_bytes, pos);
        let line_end = n;
        if eol != 999999 {
            line_end = eol;
        }
        if line_end > pos {
            let hline = bytes_slice_resp(header_bytes, pos, line_end);
            let colon: byte = ":";
            let cpos = find_bytes(hline, to_bytes(":"));
            if cpos != 999999 {
                let name = bytes_to_string(bytes_slice_resp(hline, 0, cpos))?;
                let val_start = cpos + 1;
                if val_start < hline.len() {
                    if hline[val_start] == (" " as byte) {
                        val_start = val_start + 1;
                    }
                }
                let value = bytes_to_string(bytes_slice_resp(hline, val_start, hline.len()))?;
                headers.add(name, value);
            }
        }
        if eol == 999999 {
            pos = n;
        } else {
            pos = eol + 2;
        }
    }

    let cl = incoming_content_length(headers)?;
    let body = rest;
    if transfer_encoding_is_chunked(headers.names, headers.values) == 1 {
        body = resp_decode_chunked(rest)?;
    } else {
        if cl != 999999 {
            if cl > rest.len() {
                http_err_protocol()?;
            }
            if cl < rest.len() {
                body = bytes_slice_resp(rest, 0, cl);
            }
        }
    }
    return new IncomingRequest(method, path, version, headers, body);
}

fn build_response_head(Response r) -> Vec<byte> {
    let status = r.status;
    let reason = "OK";
    if status == 404 {
        reason = "Not Found";
    } else if status == 500 {
        reason = "Internal Server Error";
    } else if status == 204 {
        reason = "No Content";
    } else if status == 201 {
        reason = "Created";
    }
    let bl = r.body.len();
    let head = "HTTP/1.1 " + int_to_dec(status) + " " + reason + "\r\nContent-Length: " + int_to_dec(bl) + "\r\n";
    let i = 0;
    let acc = head;
    let n = r.header_names.len();
    while i < n {
        acc = acc + r.header_names[i] + ": " + r.header_values[i] + "\r\n";
        i = i + 1;
    }
    acc = acc + "Connection: close\r\n\r\n";
    return to_bytes(acc);
}

fn build_response_head_keepalive(Response r) -> Vec<byte> {
    let status = r.status;
    let reason = "OK";
    if status == 404 {
        reason = "Not Found";
    } else if status == 500 {
        reason = "Internal Server Error";
    }
    let bl = r.body.len();
    let head = "HTTP/1.1 " + int_to_dec(status) + " " + reason + "\r\nContent-Length: " + int_to_dec(bl) + "\r\n";
    let i = 0;
    let acc = head;
    let n = r.header_names.len();
    while i < n {
        acc = acc + r.header_names[i] + ": " + r.header_values[i] + "\r\n";
        i = i + 1;
    }
    acc = acc + "Connection: keep-alive\r\n\r\n";
    return to_bytes(acc);
}

fn response_wants_chunked(Response r) -> int {
    return transfer_encoding_is_chunked(r.header_names, r.header_values);
}

fn build_response_head_chunked(Response r, int keep_alive) -> Vec<byte> {
    let status = r.status;
    let reason = "OK";
    if status == 404 {
        reason = "Not Found";
    } else if status == 500 {
        reason = "Internal Server Error";
    } else if status == 204 {
        reason = "No Content";
    } else if status == 201 {
        reason = "Created";
    }
    let conn = "close";
    if keep_alive == 1 {
        conn = "keep-alive";
    }
    let head = "HTTP/1.1 " + int_to_dec(status) + " " + reason + "\r\n";
    let i = 0;
    let acc = head;
    let n = r.header_names.len();
    let saw_te = 0;
    while i < n {
        acc = acc + r.header_names[i] + ": " + r.header_values[i] + "\r\n";
        if header_name_eq_ci(r.header_names[i], "Transfer-Encoding") == 1 {
            saw_te = 1;
        }
        i = i + 1;
    }
    if saw_te == 0 {
        acc = acc + "Transfer-Encoding: chunked\r\n";
    }
    acc = acc + "Connection: " + conn + "\r\n\r\n";
    return to_bytes(acc);
}

/// Serializes `r` for HTTP/1.1 with `Connection: close`.
///
/// Writes the status line, `Content-Length`, `r`'s header fields and the body.
/// When `r` has `Transfer-Encoding: chunked`, the body is sent as one chunk
/// instead and no `Content-Length` is written.
///
/// # Examples
///
/// ```
/// # use tests::assert;
/// use http::h1::encode_response;
/// use http::response::Response;
/// use string::{from_bytes, to_bytes};
///
/// let r = Response::ok();
/// r.header("Content-Type", "text/plain");
/// r.body(to_bytes("hi"));
/// let text = match from_bytes(encode_response(r)) {
///     Result::Ok(s) => s,
///     Result::Err(_) => panic "not UTF-8",
/// };
/// assert!(text == "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nhi");
/// ```
fn encode_response(Response r) -> Vec<byte> {
    if response_wants_chunked(r) == 1 {
        let head = build_response_head_chunked(r, 0);
        let body = match resp_encode_chunked(r.body) {
            Result::Ok(b) => b,
            Result::Err(_) => r.body,
        };
        return concat_bytes(head, body);
    }
    let head = build_response_head(r);
    return concat_bytes(head, r.body);
}

/// Same as `encode_response`, with `Connection: keep-alive`.
fn encode_response_keepalive(Response r) -> Vec<byte> {
    if response_wants_chunked(r) == 1 {
        let head = build_response_head_chunked(r, 1);
        let body = match resp_encode_chunked(r.body) {
            Result::Ok(b) => b,
            Result::Err(_) => r.body,
        };
        return concat_bytes(head, body);
    }
    let head = build_response_head_keepalive(r);
    return concat_bytes(head, r.body);
}

/// Decodes an HTTP/1.1 chunked body (no head) into its bytes.
///
/// Chunk extensions and trailer fields are skipped. Returns `Protocol` when the
/// input is truncated or a chunk size is not hex.
///
/// # Examples
///
/// ```
/// # use tests::assert;
/// use http::h1::{decode_chunked_body, encode_chunked_body};
/// use string::to_bytes;
///
/// let wire = match encode_chunked_body(to_bytes("hello")) {
///     Result::Ok(b) => b,
///     Result::Err(e) => panic show(e),
/// };
/// let back = match decode_chunked_body(wire) {
///     Result::Ok(b) => b,
///     Result::Err(e) => panic show(e),
/// };
/// assert!(back.len() == 5);
/// ```
fn decode_chunked_body(Vec<byte> raw) -> Result<Vec<byte>, HttpError> {
    return resp_decode_chunked(raw)?;
}

/// Encodes `body` as one chunk followed by the terminating zero-size chunk.
fn encode_chunked_body(Vec<byte> body) -> Result<Vec<byte>, HttpError> {
    return resp_encode_chunked(body)?;
}

fn incoming_wants_close(IncomingRequest req) -> int {
    return connection_is_close(req.headers);
}
