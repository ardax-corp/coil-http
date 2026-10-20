# Consume coil-http

Add this package's `src/` directory as a module root (`--root`). `conv` / `ascii` / `io::sync` come from [coil-stdlib](https://github.com/ardax-corp/coil-stdlib). HTTPS needs [coil-tls](https://github.com/ardax-corp/coil-tls) as a root and `libtls` on the FFI search path. coil reads no `coil.toml` and no `coil.lock`.

## Sibling checkout

Build `libtls` in a coil-tls checkout (`make -C ../coil-tls/native artifact`), then:

```bash
coil --root ../coil-http/src --root ../coil-tls/src --root ../coil-stdlib/src \
  --ffi-search-path ../coil-tls/native --allow-dload tls --dload-trusted tls \
  --allow-attach --allow-net main.hy
```

`--dload-pin tls=SHA256` instead of `--dload-trusted tls` pins the `libtls` build. `--allow-attach` is for TLS (`Stream.attach`); plain `http://` needs only `--allow-net`. `coil package` also needs `--ffi-native name=tls,version=0.1.0,path=../coil-tls/native` for the `tls` stem.

## With spool

This repo is tagged (`v0.1.0`):

```bash
spool add http --git https://github.com/ardax-corp/coil-http.git --version '^0.1'
```

That currently fails: this repo's `coil.toml` requires `tls` `version = "^0.1"` and coil-tls has no tags, so spool finds no matching tag. Once coil-tls is tagged, the consumer `coil.toml` looks like this:

```toml
[module]
roots = ["./src"]

[permissions]
net = true
attach = true

[ffi]
allow = ["tls"]

[dependencies]
http = { git = "https://github.com/ardax-corp/coil-http.git", version = "^0.1" }
tls = { git = "https://github.com/ardax-corp/coil-tls.git", version = "^0.1", trusted = true }
```

spool links `.spool/deps/<name>` to each checkout's `src/` and also passes each `src/` as a root (spool#30), so `use http::client::Client` resolves to `src/http/client.hy` with no extra roots.

spool also resolves each dependency's own `[ffi]` paths against its checkout (spool#38): coil-tls's `search_paths = ["./native"]` becomes `--ffi-search-path <tls checkout>/native`, and its `[[ffi.native]]` row goes to `coil package`. This repo's `./.spool/deps/tls/native` (the `scripts/spool_install.sh` layout) is skipped there, since no checkout has it. spool does not build `libtls`; build it once in the tls checkout:

```bash
make -C "$(dirname "$(readlink -f .spool/deps/tls)")/native" artifact
```

Then `spool test`, `spool build` and `spool run` work; `spool build` copies the packaged `libtls` into the natives cache, so `target/<name>` runs from any directory. A build elsewhere also works: name its directory in the consumer's own `[ffi] search_paths` (`["../coil-tls/native"]`), which come first.

Imports use the `http::` prefix (`use http::client::Client`). TLS stays `use tls::{client, server}`. WebSocket is `use http::ws::{ws_connect, ws_serve_once}`.
