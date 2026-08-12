// HTTP/2 stub (M5) — requires ALPN negotiation in the TLS stack.
use http::url::{HttpError, http_err_not_supported};

/// HTTP/2 is not supported until ALPN ships in `io::net::tls`.
fn h2_not_supported() -> Result<(), HttpError> {
    http_err_not_supported()?;
    return ();
}

/// Placeholder for future HTTP/2 client upgrade.
fn h2_connect(string url) -> Result<(), HttpError> {
    h2_not_supported()?;
    return ();
}

/// Placeholder for future HTTP/2 server settings frame.
fn h2_serve() -> Result<(), HttpError> {
    h2_not_supported()?;
    return ();
}
