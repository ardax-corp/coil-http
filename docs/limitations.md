# Limitations (v1)

- HTTP/1.1 only on the wire (see [h2.md](h2.md), [h3.md](h3.md))
- No redirects or cookies
- No chunked transfer encoding
- Connection pool reuses TCP but reads each response with `read_to_end` (works with `Connection: close` servers; keep-alive to persistent servers needs framed reads — future work)
- `coil test` harness does not support `thread::spawn`; run `coil examples/loopback.hy` for full TCP loopback
- Depends on [coil-stdlib](https://github.com/ardax-corp/coil-stdlib) (`conv`, `io::sync`) via `[module].roots`
- IPv6 URL literals not supported
- CR/LF injection in URL/method/headers → `BadUrl`
- `Content-Length` longer than body → `BadResponse`

## Compiler workarounds

- `body_len_str` / `cl_trailer` lookup tables avoid SEGV when concatenating `int_to_dec` in Result-mode request builders
- `build_request_head` hot path is raise-free
- Prefer `http://host/?q=` over bare `host?q=` in URLs

## TLS

Client: verified TLS only. Server: PEM cert/key via `Server::tls`. Requires Coil `tls` feature.
