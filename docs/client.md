# Client API

## Client

```coil
use http::client::Client;

let c = Client::new();
c.get("http://example.com/")?;
c.post("http://example.com/", body_bytes)?;
c.no_pool();  // Connection: close, no reuse
c.close();    // drain the pool (close idle sockets)
```

`Client::new()` enables connection pooling with `Connection: keep-alive`. Responses are framed by `Content-Length` or chunked transfer encoding so the connection can be reused. Call `no_pool()` for one-shot requests (matches legacy `Connection: close` behavior).

`h2_get`, `h2_post`, and `h2_send` speak HTTP/2 on a session stored on this `Client`. Cleartext (`http://`) sends the connection preface (prior knowledge). `https://` offers ALPN `h2,http/1.1` and uses HTTP/2 only when the selected protocol is `h2`; any other selection, including empty, completes the same request as HTTP/1.1 on that connection. Repeated HTTP/2 calls to the same origin reuse that connection and open new stream ids. They do not use the HTTP/1.1 pool. `close()` drains the HTTP/1.1 pool and the HTTP/2 session. Response header fields are available from `header_get`. Trailing header fields from an HTTP/2 response are available from `trailer_get`.

`fn drop()` on `Client` (and on `HttpConn` / `ConnPool` / `Server`) runs at GC time, not at last use. Prefer `c.close()` / `close_conn` for deterministic shutdown; drop is a backstop if a client or pool becomes unreachable.

## Request builder

```coil
use http::request::Request;

let req = Request::new();
req.method("PUT");
req.url("http://example.com/x");
req.header("X-Trace", "abc");
req.body(body);
c.send(req)?;
```

## Response

```coil
use http::response::{Response, parse_response, header_get};

let r = Response::ok();
r.status(201);
r.header("Content-Type", "text/plain");
r.body(to_bytes("hi"));
```

Parsed responses expose `status`, `body`, and `header_get(r, "Name")`.

## Errors

`HttpError` (derives `Show` and `Eq`):

| Variant | When |
|---|---|
| `BadUrl` | the URL (or method) does not parse or holds CR/LF |
| `InvalidHeader` | a request header name/value holds CR/LF, or a header line has no `:` |
| `UnsupportedScheme` | scheme is not `http`, `https`, `ws`, `wss` |
| `NotSupported` | HTTP/3 |
| `Protocol` | the peer broke HTTP/1.1, HTTP/2 or WebSocket framing |
| `Io(IoError)` | the socket failed; the `io` error is kept |
| `Tls(TlsError)` | the TLS layer failed (`Certificate`, `Handshake`, or `Io(IoError)`) |

```coil
use http::client::Client;
use http::url::HttpError;
use io::IoError;
use tls::error::TlsError;

fn status_or_zero(Client client, string url) -> int {
    return match client.get(url) {
        Result::Ok(r) => r.status,
        Result::Err(HttpError::Tls(TlsError::Certificate)) => 0,
        Result::Err(HttpError::Io(IoError::TimedOut)) => 0,
        Result::Err(e) => panic show(e),
    };
}
```

WebSocket URLs (`ws://`, `wss://`) use `http::ws::ws_connect`, not `Client::get`. See [ws.md](ws.md).

HTTPS uses verified TLS (`webpki` roots via [coil-tls](https://github.com/ardax-corp/coil-tls)), and `Client` always verifies. For a local dev certificate, `h2_connect_tls(url, verify, ca_pem)` (`http::h2_session`) and `ws_connect_tls` take `verify: false` or a CA PEM; on your own stream, call `tls::client::enable` with a `ClientOpts`.
