// Per-connection HTTP/1.1 framed reads (headers + Content-Length body).
use io::{Stream, close, read};
use io::sync::{read_exact};
use http::url::{HttpError, http_err_bad_response, http_err_io, http_fail_unit};
use http::request::{concat_bytes};
use http::response::{bytes_slice_resp, find_header_end, header_block_body_len, parse_chunk_size_line};

/// Stream plus bytes pulled past the current message (keep-alive / pipelining).
class HttpConn {
    inner: Stream,
    leftover: Vec<byte>,
    reusable: int,
    closed: int,
}

fn close_conn(HttpConn c) {
    if c.closed == 1 {
        return;
    }
    c.closed = 1;
    match close(c.inner) {
        Result::Ok(_) => 0,
        Result::Err(_) => 0,
    };
}

impl HttpConn {
    static fn wrap(Stream s) -> HttpConn {
        let leftover: Vec<byte> = Vec::new();
        return new HttpConn(s, leftover, 1, 0);
    }

    fn stream() -> Stream {
        return self.inner;
    }

    fn can_reuse() -> int {
        return self.reusable;
    }

    fn drop() {
        if self.closed == 0 {
            self.closed = 1;
            match close(self.inner) {
                Result::Ok(_) => 0,
                Result::Err(_) => 0,
            };
        }
        self.closed = self.closed;
    }
}

fn make_chunk() -> Vec<byte> {
    let z: byte = 0;
    let chunk: Vec<byte> = Vec::new();
    let i = 0;
    while i < 64 {
        chunk.push(z);
        i = i + 1;
    }
    return chunk;
}

fn leftover_take(HttpConn c, int n) -> Vec<byte> {
    let have = len(c.leftover);
    let take = n;
    if take > have {
        take = have;
    }
    let out = bytes_slice_resp(c.leftover, 0, take);
    if take < have {
        c.leftover = bytes_slice_resp(c.leftover, take, have);
    } else {
        let empty: Vec<byte> = Vec::new();
        c.leftover = empty;
    }
    return out;
}

fn read_n(HttpConn c, int n) -> Result<Vec<byte>, HttpError> {
    let out = leftover_take(c, n);
    let need = n - len(out);
    if need == 0 {
        return out;
    }
    let buf: Vec<byte> = Vec::new();
    let k = 0;
    while k < need {
        buf.push(0);
        k = k + 1;
    }
    let got = match read_exact(c.inner, buf) {
        Result::Ok(o) => o,
        Result::Err(_) => {
            http_err_io()?;
            Option::None
        },
    };
    match got {
        Option::None => {
            http_err_bad_response()?;
        },
        Option::Some(m) => {
            if m < need {
                http_err_bad_response()?;
            }
            let j = 0;
            while j < need {
                out.push(buf[j]);
                j = j + 1;
            }
        },
    };
    return out;
}

fn read_crlf_line(HttpConn c) -> Result<Vec<byte>, HttpError> {
    let acc: Vec<byte> = Vec::new();
    let guard = 0;
    let cr: byte = "\r";
    let lf: byte = "\n";
    while guard < 4096 {
        let b = read_n(c, 1)?;
        if len(acc) > 0 {
            if acc[len(acc) - 1] == cr {
                if b[0] == lf {
                    return bytes_slice_resp(acc, 0, len(acc) - 1);
                }
            }
        }
        acc.push(b[0]);
        guard = guard + 1;
    }
    http_err_bad_response()?;
    return acc;
}

fn read_chunked_wire(HttpConn c) -> Result<Vec<byte>, HttpError> {
    let acc: Vec<byte> = Vec::new();
    let cr: byte = "\r";
    let lf: byte = "\n";
    let keep = 1;
    while keep == 1 {
        let line = read_crlf_line(c)?;
        let i = 0;
        while i < len(line) {
            acc.push(line[i]);
            i = i + 1;
        }
        acc.push(cr);
        acc.push(lf);
        let size = parse_chunk_size_line(line)?;
        if size == 0 {
            let trail = 1;
            while trail == 1 {
                let t = read_crlf_line(c)?;
                let j = 0;
                while j < len(t) {
                    acc.push(t[j]);
                    j = j + 1;
                }
                acc.push(cr);
                acc.push(lf);
                if len(t) == 0 {
                    trail = 0;
                }
            }
            keep = 0;
        } else {
            let data = read_n(c, size)?;
            let k = 0;
            while k < len(data) {
                acc.push(data[k]);
                k = k + 1;
            }
            let nl = read_n(c, 2)?;
            if len(nl) < 2 {
                http_err_bad_response()?;
            }
            if nl[0] != cr {
                http_err_bad_response()?;
            }
            if nl[1] != lf {
                http_err_bad_response()?;
            }
            acc.push(cr);
            acc.push(lf);
        }
    }
    return acc;
}

fn append_read(Vec<byte> acc, Vec<byte> chunk, int nread) {
    let j = 0;
    while j < nread {
        acc.push(chunk[j]);
        j = j + 1;
    }
}

/// Read until CRLFCRLF, then exactly Content-Length body bytes. Extra bytes stay on `c`.
fn read_http_message(HttpConn c) -> Result<Vec<byte>, HttpError> {
    let acc = leftover_take(c, len(c.leftover));
    let chunk = make_chunk();
    let guard = 0;
    let done = 0;
    while done == 0 {
        if guard >= 256 {
            done = 1;
        }
        if done == 0 {
            let end = find_header_end(acc);
            if end != 999999 {
                done = 1;
            }
        }
        if done == 0 {
            let nopt = match read(c.inner, chunk) {
                Result::Ok(o) => o,
                Result::Err(_) => Option::None,
            };
            let nread = 0;
            let got = 0;
            match nopt {
                Option::None => {
                    if len(acc) > 0 {
                        done = 1;
                    }
                },
                Option::Some(n) => {
                    nread = n;
                    got = 1;
                },
            };
            if got == 1 {
                if nread == 0 {
                    if len(acc) > 0 {
                        done = 1;
                    }
                } else {
                    append_read(acc, chunk, nread);
                }
            }
        }
        guard = guard + 1;
    }
    let sep = find_header_end(acc);
    if sep == 999999 {
        http_fail_unit()?;
    }
    let head = bytes_slice_resp(acc, 0, sep + 4);
    let extra = bytes_slice_resp(acc, sep + 4, len(acc));
    c.leftover = extra;
    let header_bytes = bytes_slice_resp(acc, 0, sep);
    let body_len = header_block_body_len(header_bytes)?;
    if body_len == 999998 {
        let wire = read_chunked_wire(c)?;
        c.reusable = 1;
        return concat_bytes(head, wire);
    }
    if body_len == 999999 {
        return head;
    }
    let body = read_n(c, body_len)?;
    c.reusable = 1;
    return concat_bytes(head, body);
}

/// Read a full request or response message from a raw stream (no leftover yet).
fn read_request_bytes(Stream s) -> Result<Vec<byte>, HttpError> {
    let c = HttpConn::wrap(s);
    return read_http_message(c)?;
}
