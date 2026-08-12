// HTTP/3 stub (M6) — QUIC transport strategy notes.
//
// Planned approach when QUIC lands in coil:
// - Use a dedicated `io::net::quic` virtual module (UDP-based, TLS 1.3 built-in).
// - Map `http::Client` pool keys to QUIC connection IDs instead of TCP streams.
// - Server: multiplex requests on one QUIC conn via HTTP/3 streams.
// - Fallback: Alt-Svc header from H1/H2 servers advertising h3 endpoint.
//
// Until then, all h3 entry points return `HttpError::NotSupported`.
use http::url::{HttpError, http_err_not_supported};

fn h3_not_supported() -> Result<(), HttpError> {
    http_err_not_supported()?;
    return ();
}

fn h3_connect(string url) -> Result<(), HttpError> {
    h3_not_supported()?;
    return ();
}

fn h3_serve() -> Result<(), HttpError> {
    h3_not_supported()?;
    return ();
}
