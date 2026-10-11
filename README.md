# coil-http

HTTP/1.1 client and server for [Coil](https://github.com/ardax-corp/coil-lang). Extracted from coil-stdlib with a class-oriented API, connection pooling, and an extensible server handler trait.

HTTPS uses the [coil-tls](https://github.com/ardax-corp/coil-tls) package (`use tls::{client, server}`), not a compiler builtin.

## Quick start

Sibling checkouts of this repo, [coil-tls](https://github.com/ardax-corp/coil-tls) and [coil-stdlib](https://github.com/ardax-corp/coil-stdlib). coil reads no `coil.toml` or `coil.lock`, so pass roots and grants as flags. Build `libtls` first (`make -C ../coil-tls/native artifact`):

```bash
coil --root ../coil-http/src --root ../coil-tls/src --root ../coil-stdlib/src \
  --ffi-search-path ../coil-tls/native --allow-dload tls --dload-trusted tls \
  --allow-attach --allow-net main.hy
```

With [spool](https://github.com/ardax-corp/spool), `spool add http --git https://github.com/ardax-corp/coil-http.git --version '^0.1'`. That currently fails: this repo requires `tls` `^0.1` and coil-tls has no tags yet. See [docs/consume.md](docs/consume.md).

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
# from coil-http, with coil on PATH and coil-stdlib as a sibling
./scripts/spool_install.sh               # tls at the coil.lock rev into .spool/deps/tls
make -C .spool/deps/tls/native artifact
coil test --root ../coil-stdlib/src --root .spool/deps/tls/src \
  --ffi-search-path .spool/deps/tls/native \
  --allow-dload tls --dload-trusted tls --allow-attach --allow-net --allow-write
```

`scripts/spool_install.sh` runs `spool install` when spool is on PATH, which fails for the same missing coil-tls tag; without spool it checks out the `coil.lock` rev with git. Pass `--root ../coil-http/src` when running tests from another project.

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
