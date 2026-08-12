// Per-connection HTTP/1.1 request read helpers for the server.
use io::{Stream, read};
use http::url::{HttpError, http_fail_unit};
use http::response::{find_header_end};

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

/// Read bytes until the request header block ends (CRLFCRLF).
fn read_request_bytes(Stream s) -> Result<Vec<byte>, HttpError> {
    let acc: Vec<byte> = Vec::new();
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
            let nopt = match read(s, chunk) {
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
                    let j = 0;
                    while j < nread {
                        acc.push(chunk[j]);
                        j = j + 1;
                    }
                }
            }
        }
        guard = guard + 1;
    }
    if find_header_end(acc) == 999999 {
        http_fail_unit()?;
    }
    return acc;
}
