# coil-http

HTTP/1.1 client and server for [Coil](https://github.com/ardax-corp/coil-lang). Extracted from coil-stdlib with a class-oriented API, connection pooling, and an extensible server handler trait.

HTTPS uses the [coil-tls](https://github.com/ardax-corp/coil-tls) package (`use tls::{client, server}`), not a compiler builtin.

## Quick start

```toml
# coil.toml
[dependencies]
http = { git = "https://github.com/ardax-corp/coil-http.git", version = "^0.1" }
tls = { git = "https://github.com/ardax-corp/coil-tls.git", version = "^0.1" }

[module]
roots = ["./src", "./.spool/deps/http", "./.spool/deps/tls/src", "../coil-stdlib/src"]

[ffi]
search_paths = ["./.spool/deps/tls/native"]
```

`spool install` (or this repo's `scripts/spool_install.sh`) fetches tls from `coil.lock`. Build `libtls` in `.spool/deps/tls/native` so `dload("tls")` can find it. Native `.so` delivery is not a spool feature yet.

```coil
use http::client::Client;

fn main() {
    let c = Client::new();
    match c.get("https://example.com/") {
        Result::Ok(r) => { /* r.status, r.body */ },
        Result::Err(_) => { panic "request failed"; },
    };
}
```

## Test

```bash
# from coil-http (coil on PATH or ../coil-lang/target/debug/coil)
# siblings: coil-lang, coil-stdlib; tls sources from coil.lock
./scripts/spool_install.sh
make -C .spool/deps/tls/native artifact
coil test

# or from coil-lang checkout:
cargo build
./target/debug/coil test ../coil-http/tests
```

Add `../coil-http/src` to your `[module].roots` when running tests from another project.

## Layout

| Path | Role |
|------|------|
| `src/http/url.hy` | `Url`, `Headers`, `HttpError`, `parse_url`, `find_bytes` |
| `src/http/request.hy` | `Request` builder, `build_request_head` |
| `src/http/response.hy` | `Response` builder, `parse_response` |
| `src/http/h1.hy` | Server request parse, response encode |
| `src/http/client.hy` | `Client::get` / `post` / `send` |
| `src/http/server.hy` | `Server`, `HttpHandler` trait |
| `src/http/conn.hy` | Request read helpers |
| `src/http/pool.hy` | TCP/TLS connection pool (keep-alive) |
| `src/http/h2.hy` | HTTP/2 framing, HPACK, prior-knowledge + TLS ALPN |
| `src/http/ws.hy` | WebSocket RFC 6455 (H1 upgrade + framing) |
| `src/http/sha1.hy` | SHA-1 for `Sec-WebSocket-Accept` only |
| `src/http/h3.hy` | HTTP/3 stub |

See [docs/](docs/) for API details.

## License

MIT — see [LICENSE](LICENSE).
