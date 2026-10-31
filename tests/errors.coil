// HttpError keeps the lower layer's error: Io(IoError), Tls(TlsError).
use tests::assert;
use io::IoError;
use tls::error::TlsError;
use string::format;
use http::url::HttpError;
use http::server::Server;

test("bound_port without bind is Io(InvalidInput)") {
    let srv = Server::new();
    let ok = match srv.bound_port() {
        Result::Ok(_) => false,
        Result::Err(e) => e == HttpError::Io(IoError::InvalidInput),
    };
    assert!(ok, "expected Io(InvalidInput)");
}

test("HttpError shows the wrapped error") {
    assert!(format("%v", HttpError::Io(IoError::TimedOut)) == "HttpError::Io(TimedOut)", "Io show");
    assert!(
        format("%v", HttpError::Tls(TlsError::Certificate)) ==
        "HttpError::Tls(TlsError::Certificate)",
        "Tls show",
    );
}
