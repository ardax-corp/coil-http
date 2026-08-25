# Consume coil-http

Add this package's `src/` directory as a module root. `conv` / `ascii` / `io::sync` come from [coil-stdlib](https://github.com/ardax-corp/coil-stdlib). HTTPS needs [coil-tls](https://github.com/ardax-corp/coil-tls) on `roots` and `libtls` on `[ffi] search_paths`:

```toml
[module]
roots = ["./src", "../coil-http/src", "../coil-stdlib/src", "../coil-tls/src"]

[ffi]
search_paths = ["../coil-tls/native"]
```

Build the coil-tls cdylib so `native/libtls.so` (or `.dylib` / `tls.dll`) exists before `coil test` / `https://` requests.

Via spool (when published):

```toml
[dependencies]
http = { git = "https://github.com/ardax-corp/coil-http.git", version = "^0.1" }
tls = { git = "https://github.com/ardax-corp/coil-tls.git", version = "^0.1" }

[module]
roots = ["./src", "./.spool/deps/http", "./.spool/deps/tls/src"]

[ffi]
search_paths = ["./.spool/deps/tls/native"]
```

Imports use the `http::` prefix (`use http::client::Client`). TLS stays `use tls::{client, server}`.
