# coil-http

HTTP/1.1 and HTTP/2 client and server, plus WebSocket, for [Coil](https://github.com/ardax-corp/coil-lang). Extracted from coil-stdlib with a class-oriented API, connection pooling, and an extensible server handler trait.

HTTPS uses the [coil-tls](https://github.com/ardax-corp/coil-tls) package (`use tls::{client, server}`), not a compiler builtin.

## Quick start

A client:

```coil
use http::client::Client;
use io::IoError;
use io::sync::println;

fn main() -> Result<(), IoError> {
    let c = Client::new();
    let r = match c.get("https://example.com/") {
        Result::Ok(r) => r,
        Result::Err(e) => panic show(e),
    };
    println("status " + show(r.status) + ", " + show(r.body.len()) + " bytes")?;
    c.close();
    return ();
}
```

A server (`curl http://127.0.0.1:8080/hi` answers `hello from /hi`):

```coil
use http::server::{HttpHandler, Server, serve};
use http::h1::IncomingRequest;
use http::response::Response;
use http::url::HttpError;
use string::to_bytes;

class Hello {}

impl HttpHandler for Hello {
    fn handle(Hello self, IncomingRequest req) -> Response {
        let r = Response::ok();
        r.header("Content-Type", "text/plain");
        r.body(to_bytes("hello from " + req.path_val() + "\n"));
        return r;
    }
}

fn main() -> Result<(), HttpError> {
    let srv = Server::new();
    srv.bind("127.0.0.1", 8080)?;
    serve(srv, new Hello())?;
    return ();
}
```

## Use it

With [spool](https://github.com/ardax-corp/spool), pin a commit (the `v0.1.0` tag predates the current coil-tls requirement and does not resolve):

```bash
spool add http --git https://github.com/ardax-corp/coil-http.git --rev <commit SHA>
```

Or with plain `coil` and sibling checkouts of this repo, [coil-tls](https://github.com/ardax-corp/coil-tls) and [coil-stdlib](https://github.com/ardax-corp/coil-stdlib). coil reads no `coil.toml` or `coil.lock`, so pass roots and grants as flags. Build `libtls` first (`make -C ../coil-tls/native artifact`):

```bash
coil --root ../coil-http/src --root ../coil-tls/src --root ../coil-stdlib/src \
  --ffi-search-path ../coil-tls/native --allow-dload tls --dload-trusted tls \
  --allow-attach --allow-net main.hy
```

Plain `http://` needs only `--allow-net`. See [docs/consume.md](docs/consume.md) for the full consumer setup.

## Test

```bash
# from coil-http, with coil on PATH and coil-stdlib as a sibling
./scripts/spool_install.sh               # tls at the coil.lock rev into .spool/deps/tls
make -C .spool/deps/tls/native artifact
coil test --root ../coil-stdlib/src --root .spool/deps/tls/src \
  --ffi-search-path .spool/deps/tls/native \
  --allow-dload tls --dload-trusted tls --allow-attach --allow-net --allow-write
```

`coil test` also runs the `///` doc examples in `src/`. `scripts/spool_install.sh` runs `spool install` when spool is on PATH; without spool it checks out the `coil.lock` rev with git. The socket loopbacks in `examples/` need threads, which the test harness does not have: run them with `coil` and the same flags (CI greps each for `ok`).

## Modules

| Module | For |
|------|------|
| `http::client` | `Client`: `get` / `post` / `send` over HTTP/1.1 with keep-alive pooling, `h2_get` / `h2_post` / `h2_send` over HTTP/2 |
| `http::request` | `Request` builder (method, URL, header fields, body) |
| `http::response` | `Response` (status, header fields, body, HTTP/2 trailers), `header_get`, `parse_response` |
| `http::url` | `parse_url` / `Url`, `Headers`, and `HttpError`, the error type of the whole package |
| `http::server` | `Server`, the `HttpHandler` trait, and the serve loops (`serve`, `h2_serve_all`, ...) |
| `http::h1` | `IncomingRequest` (what a handler receives), HTTP/1.1 request parse and response encode |
| `http::ws` | WebSocket (RFC 6455) over an HTTP/1.1 upgrade: `ws_connect`, `ws_serve_once`, framing |
| `http::pool` | `ConnPool`, the per-client pool of idle HTTP/1.1 connections |
| `http::conn` | `HttpConn`: framed HTTP/1.1 message reads on a socket |
| `http::h2` | HTTP/2 frames, connection preface, ALPN helpers |
| `http::h2_session` | `H2Session` (in-memory HTTP/2 connection state), one-shot `h2_request` / `h2_connect` |
| `http::hpack` | HPACK header compression (RFC 7541) |
| `http::sha1` | SHA-1, for the WebSocket handshake only |
| `http::h3` | HTTP/3 placeholder (returns `NotSupported`) |

Every public item has `///` docs with examples. See [docs/](docs/) for topic guides and [docs/limitations.md](docs/limitations.md) for what v1 does not do.

## License

MIT — see [LICENSE](LICENSE).
