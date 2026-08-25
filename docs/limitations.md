# Limitations (v1)

- HTTP/1.1 only on the wire (see [h2.md](h2.md), [h3.md](h3.md))
- No redirects or cookies
- Connection pool reuses TCP and frames each message by `Content-Length` or chunked transfer encoding
- `fn drop()` on `HttpConn` / `ConnPool` / `Client` / `Server` closes owned sockets at GC time (and VM teardown), not RAII. Prefer `Client::close` / `close_conn` when shutdown must happen now
- `coil test` harness does not support `thread::spawn`; run `coil examples/loopback.hy` for full TCP loopback
- Depends on [coil-stdlib](https://github.com/ardax-corp/coil-stdlib) (`conv`, `io::sync`) and [coil-tls](https://github.com/ardax-corp/coil-tls) via `[module].roots` / `[ffi] search_paths`
- IPv6 URL literals not supported
- CR/LF injection in URL/method/headers → `BadUrl`
- `Content-Length` longer than body → `BadResponse`

## Compiler workarounds

- `body_len_str` / `cl_trailer` lookup tables avoid SEGV when concatenating `int_to_dec` in Result-mode request builders
- `build_request_head` hot path is raise-free
- Prefer `http://host/?q=` over bare `host?q=` in URLs

## TLS

Client: verified TLS only. Server: PEM cert/key via `Server::tls`. Requires the [coil-tls](https://github.com/ardax-corp/coil-tls) package (`use tls::{client, server}`) and a built `libtls`, not a Coil `tls` Cargo feature.
