# Server API

## Server

```coil
use http::server::{Server, HttpHandler, serve};
use http::h1::IncomingRequest;
use http::response::Response;

class MyHandler {}

impl HttpHandler<MyHandler> {
    fn handle(MyHandler self, IncomingRequest req) -> Response {
        let r = Response::ok();
        r.header("Content-Type", "text/plain");
        r.body(to_bytes("ok"));
        return r;
    }
}

fn main() {
    let srv = Server::new();
    srv.bind("127.0.0.1", 8080)?;
    // srv.tls(cert_pem, key_pem);  // optional TLS
    serve(srv, new MyHandler())?;
}
```

| Method | Role |
|--------|------|
| `bind(host, port)` | Listen (`port` 0 = ephemeral) |
| `tls(cert, key)` | Enable TLS on accepted connections |
| `bound_port()` | Port after `bind(..., 0)` |
| `serve_once(handler)` | Accept one connection, one request |
| `serve_one_client(handler)` | Accept one connection, keep-alive until close |
| `serve(handler)` | Accept loop |

## IncomingRequest

Parsed via `http::h1::parse_request`. Accessors: `method_val()`, `path_val()`, `headers_val()`, `body_val()`.

## Wire encoding

`http::h1::encode_response` builds status line + headers + body (`Connection: close` by default). `serve` uses `encode_response_keepalive` when the client did not send `Connection: close`. Set `Transfer-Encoding: chunked` on the response to emit a chunked body instead of `Content-Length`.
