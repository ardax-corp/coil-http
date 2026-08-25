// Compile/resolve: `use tls::{client, server}` typechecks and libtls is on [ffi] search_paths.
use io::{open};
use ffi::{dload};
use tls::client::enable as tls_client_enable;
use tls::server::enable as tls_server_enable;

test("tls client enable typechecks and rejects non-TCP") {
    let path = "/tmp/coil_http_tls_client_resolve.bin";
    let ok = match open(path, "w") {
        Result::Ok(s) => match tls_client_enable(s, "127.0.0.1", { verify: true, ca_pem: Option::None, ca_path: Option::None, timeout_ms: 0, alpn: "" }) {
            Result::Ok(_) => 0,
            Result::Err(_) => 1,
        },
        Result::Err(_) => 9,
    };
    assert(ok == 1, "non-TCP enable")?;
}

test("tls server enable typechecks and rejects non-TCP") {
    let path = "/tmp/coil_http_tls_server_resolve.bin";
    let ok = match open(path, "w") {
        Result::Ok(s) => match tls_server_enable(s, { cert_pem: "x", key_pem: "y", timeout_ms: 0, client_ca_pem: "", alpn: "" }) {
            Result::Ok(_) => 0,
            Result::Err(_) => 1,
        },
        Result::Err(_) => 9,
    };
    assert(ok == 1, "non-TCP server enable")?;
}

test("libtls dload resolves") {
    match dload("tls") {
        Result::Ok(h) => {
            assert(h != 0, "libtls handle")?;
        },
        Result::Err(e) => panic e.message,
    };
}
