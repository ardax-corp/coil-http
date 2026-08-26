// Compile/resolve: package enable with ClientOpts/ServerOpts typechecks; libtls is on [ffi] search_paths.
use io::{open};
use ffi::{dload};
use tls::client::{enable as tls_client_enable, ClientOpts};
use tls::server::{enable as tls_server_enable, ServerOpts};

test("tls client enable typechecks and rejects non-TCP") {
    let path = "/tmp/coil_http_tls_client_resolve.bin";
    let ok = match open(path, "w") {
        Result::Ok(s) => match tls_client_enable(s, "127.0.0.1", new ClientOpts(true, Option::None, Option::None, 0, "")) {
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
        Result::Ok(s) => match tls_server_enable(s, new ServerOpts("x", "y", 0, "", "")) {
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
