# coil-http documentation

Userland HTTP/1.1 client and server for Coil programs.

| Doc | Topic |
|-----|-------|
| [consume.md](consume.md) | Add to `coil.toml` roots |
| [client.md](client.md) | `Client`, `Request`, pooling |
| [server.md](server.md) | `Server`, `HttpHandler` |
| [limitations.md](limitations.md) | v1 scope and compiler notes |
| [h2.md](h2.md) | HTTP/2 framing, prior-knowledge, TLS ALPN |
| [h3.md](h3.md) | HTTP/3 stub / QUIC strategy |

## Requirements

- Coil with `tls` feature (default) for `https://`
- `thread` module for loopback / concurrent server examples
