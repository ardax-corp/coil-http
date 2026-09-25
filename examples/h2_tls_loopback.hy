// TLS HTTP/2 ALPN loopback. Package enable with ClientOpts/ServerOpts (ALPN h2).
// Server enable in spawn, client enable on the root, then a real GET.
// Spawned workers dload ./native/libtls.so (empty FFI search_paths).
use thread::{Sender, channel, join, recv, send as thread_send, spawn};
use conv::{int_to_dec};
use string::{to_bytes};
use io::{stdout, IoError};
use io::net::tcp::{listen, connect, local_addr};
use io::sync::{accept_wait, write_all};
use tls::client::{enable as tls_client_enable, ClientOpts};
use tls::server::{enable as tls_server_enable, ServerOpts};
use http::h1::IncomingRequest;
use http::response::Response;
use http::h2::{h2_client_alpn, h2_server_alpn};
use http::h2_session::{h2_get_over_h2};
use http::server::{HttpHandler, h2_serve_conn};
use http::url::{parse_url};

class TlsHandler {}

impl HttpHandler for TlsHandler {
    fn handle(TlsHandler self, IncomingRequest req) -> Response {
        let _m = req.method_val();
        let r = Response::ok();
        r.status(201);
        r.body(to_bytes("from-handler"));
        return r;
    }
}
