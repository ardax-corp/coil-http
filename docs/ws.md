# WebSocket (RFC 6455)

WebSocket runs **on top of HTTP/1.1** in this package: an upgrade handshake, then framed messages on the same TCP (or TLS) stream. It is not a separate transport and does not require HTTP/2.

`ws://` is cleartext. `wss://` uses [coil-tls](https://github.com/ardax-corp/coil-tls) the same way HTTPS does.

`Sec-WebSocket-Accept` is SHA-1(key + GUID) then Base64. SHA-1 is a small pure-Coil helper in `http::sha1` (handshake only). Base64 is stdlib `encoding`. There is no HostInvoke and no SHA-1 in coil-lang / coil-crypto.

## Client

```coil
use http::ws::{ws_connect, ws_recv, ws_send_text, ws_send_close, ws_close};

let c = ws_connect("ws://127.0.0.1:8080/echo")?;
ws_send_text(c, "hello")?;
let f = ws_recv(c)?;  // f.opcode, f.payload
ws_send_close(c)?;
ws_close(c);
```

| Function | Role |
|----------|------|
| `ws_connect(url)` | HTTP/1.1 upgrade; `wss://` is verified TLS |
| `ws_connect_tls(url, verify, ca_pem)` | Same, with TLS options (`ws://` ignores them) |
| `ws_connect_key(url, key)` | Caller-supplied `Sec-WebSocket-Key` (tests) |
| `ws_send_text` / `ws_send_bin` | Data frames (client masks) |
| `ws_send_ping` / `ws_send_pong` / `ws_send_close` | Control |
| `ws_recv` | One complete frame (unmasks if needed) |
| `ws_close` | Close the socket |

## Server

```coil
use http::server::Server;
use http::ws::{ws_echo_loop, ws_serve_once};

let srv = Server::new();
srv.bind("127.0.0.1", 8080)?;
let c = ws_serve_once(srv)?;  // accept + upgrade
ws_echo_loop(c)?;
```

`ws_is_upgrade_req` / `ws_upgrade` apply the handshake to an already-read `IncomingRequest` on an `HttpConn` if you parse the GET yourself.

`ws_echo_loop` echoes text/binary, answers ping with pong, and stops on close.

## Framing

`encode_ws_frame` / `decode_ws_frame` implement FIN, opcode, MASK, 7/16/64-bit length. Clients always mask outbound frames; servers never do. RSV bits, FIN=0 fragments, and payloads over 1 MiB are rejected. v1 does not assemble continuations, negotiate extensions, or speak WebSocket over HTTP/2.

## Tests and loopback

Unit tests cover SHA-1 vectors, the RFC accept-key example, and frame encode/decode (`coil test`).

Full TCP echo is `examples/ws_loopback.hy`. **`coil test` cannot `thread::spawn`**; run:

```bash
coil examples/ws_loopback.hy
```

CI greps that example for `ok`.
