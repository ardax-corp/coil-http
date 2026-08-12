// HTTP/1.1 wire helpers shared by client and server.
use io::{to_bytes};
use conv::{int_to_dec};
use http::url::{
    Headers,
    HttpError,
    bytes_to_string,
    find_bytes,
    header_name_eq_ci,
    http_err_bad_response,
};
use http::request::{concat_bytes};
use http::response::{Response, find_crlf, find_header_end, bytes_slice_resp, parse_int_bytes};

/// Parsed inbound HTTP/1.1 request (server side).
class IncomingRequest {
    method: string,
    path: string,
    version: string,
    headers: Headers,
    body: Vec<byte>,
}

impl IncomingRequest {
    fn method_val() -> string {
        return self.method;
    }

    fn path_val() -> string {
        return self.path;
    }

    fn headers_val() -> Headers {
        return self.headers;
    }

    fn body_val() -> Vec<byte> {
        return self.body;
    }
}

fn incoming_content_length(Headers h) -> Result<int, HttpError> {
    let i = 0;
    let n = len(h.names);
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
    let n = len(h.names);
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

/// Parse raw HTTP/1.1 request bytes (head + body) into `IncomingRequest`.
fn parse_request(Vec<byte> raw) -> Result<IncomingRequest, HttpError> {
    let sep = find_header_end(raw);
    if sep == 999999 {
        http_err_bad_response()?;
    }
    let header_bytes = bytes_slice_resp(raw, 0, sep);
    let rest = bytes_slice_resp(raw, sep + 4, len(raw));

    let eol0 = find_crlf(header_bytes, 0);
    if eol0 == 999999 {
        http_err_bad_response()?;
    }
    let line = bytes_slice_resp(header_bytes, 0, eol0);
    let sp: byte = " ";
    let ln = len(line);
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
        http_err_bad_response()?;
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
        http_err_bad_response()?;
    }
    let path = bytes_to_string(bytes_slice_resp(line, p_start, p_end))?;

    let v_start = p_end + 1;
    let version = bytes_to_string(bytes_slice_resp(line, v_start, ln))?;

    let headers = Headers::new();
    let pos = eol0 + 2;
    let n = len(header_bytes);
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
                if val_start < len(hline) {
                    if hline[val_start] == (" " as byte) {
                        val_start = val_start + 1;
                    }
                }
                let value = bytes_to_string(bytes_slice_resp(hline, val_start, len(hline)))?;
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
    if cl != 999999 {
        if cl > len(rest) {
            http_err_bad_response()?;
        }
        if cl < len(rest) {
            body = bytes_slice_resp(rest, 0, cl);
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
    let bl = len(r.body);
    let head = "HTTP/1.1 " + int_to_dec(status) + " " + reason + "\r\nContent-Length: " + int_to_dec(bl) + "\r\n";
    let i = 0;
    let acc = head;
    let n = len(r.header_names);
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
    let bl = len(r.body);
    let head = "HTTP/1.1 " + int_to_dec(status) + " " + reason + "\r\nContent-Length: " + int_to_dec(bl) + "\r\n";
    let i = 0;
    let acc = head;
    let n = len(r.header_names);
    while i < n {
        acc = acc + r.header_names[i] + ": " + r.header_values[i] + "\r\n";
        i = i + 1;
    }
    acc = acc + "Connection: keep-alive\r\n\r\n";
    return to_bytes(acc);
}

/// Encode response status line + headers + body for the wire.
fn encode_response(Response r) -> Vec<byte> {
    let head = build_response_head(r);
    return concat_bytes(head, r.body);
}

/// Chunked transfer-encoding is not supported in v1; returns Err.
fn decode_chunked_body(Vec<byte> raw) -> Result<Vec<byte>, HttpError> {
    http_err_bad_response()?;
    return raw;
}

/// Chunked transfer-encoding is not supported in v1; returns Err.
fn encode_chunked_body(Vec<byte> body) -> Result<Vec<byte>, HttpError> {
    http_err_bad_response()?;
    return body;
}

fn incoming_wants_close(IncomingRequest req) -> int {
    return connection_is_close(req.headers);
}
