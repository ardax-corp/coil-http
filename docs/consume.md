# Consume coil-http

Add this package's `src/` directory as a module root:

```toml
[module]
roots = ["./src", "../coil-http/src"]
```

Via spool (when published):

```toml
[dependencies]
http = { git = "https://github.com/ardax-corp/coil-http.git", version = "^0.1" }

[module]
roots = ["./src", "./.spool/deps/http"]
```

Imports use the `http::` prefix (`use http::client::Client`).
