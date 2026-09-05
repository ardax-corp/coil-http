# Limitations (v1)

- HTTP/1.1 on the wire; HTTP/2 cleartext prior-knowledge and TLS ALPN `h2`; WebSocket over H1 upgrade (see [h2.md](h2.md), [ws.md](ws.md), [h3.md](h3.md))
- No redirects or cookies
- Connection pool reuses TCP and frames each message by `Content-Length` or chunked transfer encoding
- `fn drop()` on `HttpConn` / `ConnPool` / `Client` / `Server` closes owned sockets at GC time (and VM teardown), not RAII. Prefer `Client::close` / `close_conn` when shutdown must happen now
- `coil test` harness does not support `thread::spawn`; run `coil examples/loopback.hy` / `examples/ws_loopback.hy` for full TCP loopback
- Depends on [coil-stdlib](https://github.com/ardax-corp/coil-stdlib) (`conv`, `io::sync`) as a sibling root and [coil-tls](https://github.com/ardax-corp/coil-tls) via spool (`coil.lock` → `.spool/deps/tls`). `libtls` still needs a local native build on `[ffi] search_paths`
- WebSocket v1: H1 upgrade only (no HTTP/2, no extensions, no fragmented messages)
- IPv6 URL literals not supported
- CR/LF injection in URL/method/headers → `BadUrl`
- `Content-Length` longer than body → `BadResponse`

## Compiler workarounds

- `body_len_str` / `cl_trailer` lookup tables avoid SEGV when concatenating `int_to_dec` in Result-mode request builders
- `build_request_head` hot path is raise-free
- Prefer `http://host/?q=` over bare `host?q=` in URLs

## TLS

Client: verified TLS only (`new ClientOpts(true, ...)`). Server: PEM cert/key via `Server::tls` (`new ServerOpts(...)`). Requires the [coil-tls](https://github.com/ardax-corp/coil-tls) package (`use tls::{client, server}::enable`) and a built `libtls`, not a Coil `tls` Cargo feature.
