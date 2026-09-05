# Consume coil-http

Add this package's `src/` directory as a module root. `conv` / `ascii` / `io::sync` come from [coil-stdlib](https://github.com/ardax-corp/coil-stdlib). HTTPS needs [coil-tls](https://github.com/ardax-corp/coil-tls) on `roots` and `libtls` on `[ffi] search_paths`.

This package depends on `tls` via spool (`coil.lock`), not a `../coil-tls` path:

```toml
[dependencies]
tls = { git = "https://github.com/ardax-corp/coil-tls.git", version = "^0.1" }

[module]
roots = ["./src", "../coil-stdlib/src", "./.spool/deps/tls/src"]

[ffi]
search_paths = ["./.spool/deps/tls/native"]
```

The compiler requires `version` on git deps; `coil.lock` is the pin until [COI-219](https://linear.app/ardax/issue/COI-219).

`spool install` (or `scripts/spool_install.sh` when the spool CLI is not on PATH) materializes `.spool/deps/tls` from `coil.lock`. Build the cdylib in that tree (`make -C .spool/deps/tls/native artifact`) so `libtls.so` (or `.dylib` / `tls.dll`) sits on `[ffi] search_paths`. Native artifact publishing is not spool's job yet ([COI-60](https://linear.app/ardax/issue/COI-60)).

Via spool (when this package is published):

```toml
[dependencies]
http = { git = "https://github.com/ardax-corp/coil-http.git", version = "^0.1" }
tls = { git = "https://github.com/ardax-corp/coil-tls.git", version = "^0.1" }

[module]
roots = ["./src", "./.spool/deps/http", "./.spool/deps/tls/src"]

[ffi]
search_paths = ["./.spool/deps/tls/native"]
```

Imports use the `http::` prefix (`use http::client::Client`). TLS stays `use tls::{client, server}`. WebSocket is `use http::ws::{ws_connect, ws_serve_once}`.
