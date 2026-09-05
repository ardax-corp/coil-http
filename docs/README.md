# coil-http documentation

Userland HTTP/1.1 client and server for Coil programs.

| Doc | Topic |
|-----|-------|
| [consume.md](consume.md) | Add to `coil.toml` roots |
| [client.md](client.md) | `Client`, `Request`, pooling |
| [server.md](server.md) | `Server`, `HttpHandler` |
| [limitations.md](limitations.md) | v1 scope and compiler notes |
| [h2.md](h2.md) | HTTP/2 framing, HPACK, ALPN |
| [ws.md](ws.md) | WebSocket RFC 6455 (H1 upgrade) |
| [h3.md](h3.md) | HTTP/3 stub / QUIC strategy |

## Requirements

- [coil-tls](https://github.com/ardax-corp/coil-tls) on `[module].roots` and `libtls` on `[ffi] search_paths` for `https://`
- `thread` module for loopback / concurrent server examples
