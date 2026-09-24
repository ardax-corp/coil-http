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

`h2_get`, `h2_post`, and `h2_send` speak HTTP/2. Cleartext (`http://`) sends the connection preface (prior knowledge). `https://` offers ALPN `h2,http/1.1` and uses HTTP/2 only when the selected protocol is `h2`; any other selection, including empty, completes the same request as HTTP/1.1 on that connection. These calls do not use the HTTP/1.1 pool. Response header fields are available from `header_get`. Trailing header fields from an HTTP/2 response are available from `trailer_get`.

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

`HttpError`: `BadUrl`, `BadResponse`, `UnsupportedScheme`, `Io`, `NotSupported`.

WebSocket URLs (`ws://`, `wss://`) use `http::ws::ws_connect`, not `Client::get`. See [ws.md](ws.md).

HTTPS uses verified TLS (`webpki` roots via [coil-tls](https://github.com/ardax-corp/coil-tls)). Local dev certs need `tls::client::enable` with a `ClientOpts` (`verify: false` and/or `ca_pem`).
