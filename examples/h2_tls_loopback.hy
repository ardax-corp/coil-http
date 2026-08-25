// TLS HTTP/2 ALPN loopback (COI-116 / coil-lang #200).
// Server enable in spawn, client enable on the root, ALPN `h2`, then GET.
use thread::{Sender, channel, join, recv, send as thread_send, spawn};
use conv::{int_to_dec};
use string::{to_bytes};
use io::{stdout, await_readable, IoError};
use io::net::tcp::{listen, connect, accept, local_addr};
use io::sync::{write_all};
use tls::client::enable as tls_client_enable;
use tls::server::enable as tls_server_enable;
use tls::alpn_protocol;
use http::h2::{h2_get_over_h2};
use http::server::{h2_serve_conn};
use http::url::{parse_url};

fn cert_pem() -> string {
    return "-----BEGIN CERTIFICATE-----\nMIIDTTCCAjWgAwIBAgIULZZHw6Gv1CG49dSJ/JsIWAC09uYwDQYJKoZIhvcNAQEL\nBQAwGzEZMBcGA1UEAwwQY29pbC10bHMtdGVzdC1jYTAeFw0yNjA4MjUxMjM2MTda\nFw0zNjA4MjIxMjM2MTdaMBQxEjAQBgNVBAMMCWxvY2FsaG9zdDCCASIwDQYJKoZI\nhvcNAQEBBQADggEPADCCAQoCggEBAKsFaAp1MrBsZ5AenNOJOrHdzVDnV1o2V42O\naTUbNRmzRF/IYXceRj5kGZQShs6kAaYzXRPog2hd2MZc60MjNqNBEfe3eZ12+E6J\nf/Rz44zbFXj2CO7bqf3NQhbKa+1oxpzx/GV2+4M5Z2FgOVRfxKYgoXDzn99NxBzK\nAr7E7Ggd3snXwBu6k/lvxf9wUbkj9FZyJTrSkMSoz5rfNzBBNFbAQT/TamJGmht9\ni/+wk2JwbxfH1cjrJamS+sN7DFPgELVsNJwr0BlkPNnrxiQEqJ7mj2Kj9hcfjIVx\nWUj/xenVHrBQ4FpvyX7WybT9M2BrkGWfOw+20qSuhIeCSqa4swcCAwEAAaOBjzCB\njDAJBgNVHRMEAjAAMA4GA1UdDwEB/wQEAwIFoDATBgNVHSUEDDAKBggrBgEFBQcD\nATAaBgNVHREEEzARgglsb2NhbGhvc3SHBH8AAAEwHQYDVR0OBBYEFH+Z4z5GgmrD\nGrruwTh5IpG4tBc+MB8GA1UdIwQYMBaAFAFFn3ZWMg3CtulzlnYkJs2ecKb+MA0G\nCSqGSIb3DQEBCwUAA4IBAQC97MSOUVZbYlUrwLun5ZQCJKkjIhHDezMmJJWFFg/t\nnWdYtOloWHmY0tOsa6tAvF+0zYc4YZdkpeSnbqH+Mk41znf+A/Js0i3JKK2hJ1Eu\nBQG64LjCnZwVKqLxrvxlzbKNIIEUwf0CktTCok7wlhYWYZK9b9+4soAPgF2KoIX3\nj6TnG3xBFF06rzybsbSaHKVn7flUaTxj+05NtLBbMdzqle3xQX3Dz34klFTQdkTl\nlGz1K09Rl6uVKsU1SgNsm5cxAOtW8HGDinTTPPCuoOBhXWUCWS9U9zsk20VQPH7q\nq5up6N6FnhYpQ5eBDWSeJryILFZkK8/tASxKgeyHHaBh\n-----END CERTIFICATE-----\n";
}

fn key_pem() -> string {
    return "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCrBWgKdTKwbGeQ\nHpzTiTqx3c1Q51daNleNjmk1GzUZs0RfyGF3HkY+ZBmUEobOpAGmM10T6INoXdjG\nXOtDIzajQRH3t3mddvhOiX/0c+OM2xV49gju26n9zUIWymvtaMac8fxldvuDOWdh\nYDlUX8SmIKFw85/fTcQcygK+xOxoHd7J18AbupP5b8X/cFG5I/RWciU60pDEqM+a\n3zcwQTRWwEE/02piRpobfYv/sJNicG8Xx9XI6yWpkvrDewxT4BC1bDScK9AZZDzZ\n68YkBKie5o9io/YXH4yFcVlI/8Xp1R6wUOBab8l+1sm0/TNga5BlnzsPttKkroSH\ngkqmuLMHAgMBAAECggEAA2mY55CEG1CACbh0QT8dP5xUTJESxXDAWXymE8WzTwwS\nyRh9/WFj96DwTVIuhD2lVmDy/zX/nUI2ITfy1J5r9WD6HOfGOPXW3MMfA8xmL3k8\nDSa+C31KZij41x/HfIkl+wHtgXbMBcfMJmP3Pa91hJBLhS31tDNG8c4dtOguawgy\nuG3jiJNdnk7DFgAXEt/SACroEN8q9O0LEqSd85OP2HcIoz8UNKT1y5k0h5t2WIny\n2xk0SKx4iSUk5LvjHgOLpc7VtgOcNFkprRoALgFF/LJprL4a8PPgjMNmgNojTNLM\nK89+Fe5MnlL2rn52EfN3k/nkOzfC0r0jYOtaGj4LFQKBgQDwaCPOUlDfASHk1S1M\nTvl+G5BE5VhAzIz/C0Qse8b4fSHQlNCw4OWMVwwUYxFTNTppn+LP7nN14kv5/m3W\nQn31dFZSYzIpuc2s/J+YusoGbkWHcZsh1yi3RMnzJKMTEzyopnExy8nL6BXYOQQg\nwDaC1LXb7axALsD6vwJHBCyuZQKBgQC2HSULXEZfbS3Lj2XfRHGCY6iR20aMAtYk\nhtFeBfOfWfct4JuCBXywFUEbrcXEPQyjUqYMl4t5+r9e1qKMmF6XGnb6i+B9mp4E\nCZp3hqlW4rIRZ9joyzAI3hO9t2Rcv8AasZdtIOMAHBJ6Ssnrm5R2Y5QnfsGkZIMy\nL/SCQYR++wKBgQDrSTEKA/xMVaJjgNQlpAGAj9+B3miies/f6ZneY4IXvvgyWQNq\nqaFf2e3johXZtvWlXKsyUDDGhiVP1diP42G9sg+t8JGuzr9id5iHdQC2jIQWDHUF\nCLw7qeJwykGkMKakdMnCL64fl9SRWzQUDasMHryiM5nq8xdCEWFcOdS1FQKBgDX/\nXkSID7WrwbBhzGru+FkZA5p70ech0Cz0bI/cY+gT3N6VgoaC6f2rz6pNVB5jm6Ox\nldqV9J0uZB/StE/LvgA/sJeJcf7MIZ5A2rQmEX/Zp8LRb9dWp995OZE/F1sI4AUK\nM0QARE58BF6OXmCluNeBnyQ2yWPdCamP3ofgtVCRAoGATHCkcsAnWdhfIWloU6Ng\n9RRA5HfZ/tZFnBqOKf3pRVdM0dZBrAG1Srs5uUgz0TyDwIVK8fl1lMgk/oAB/tV9\nmtsskqWgKGl8UKXrstp5AA+1oKAAcSfbEye4OxOY/n3cOrvCQbKiIKMxMxVSDMtF\ns5cT1ga2yvQU9Lg+hGOC4VA=\n-----END PRIVATE KEY-----\n";
}

fn io_err_tag(IoError e) -> string {
    return match e {
        IoError::WouldBlock => "WouldBlock",
        IoError::NotFound => "NotFound",
        IoError::PermissionDenied => "PermissionDenied",
        IoError::AlreadyClosed => "AlreadyClosed",
        IoError::InvalidInput => "InvalidInput",
        IoError::Other => "Other",
        IoError::NotADirectory => "NotADirectory",
        IoError::AlreadyExists => "AlreadyExists",
        IoError::TimedOut => "TimedOut",
        IoError::Truncated => "Truncated",
        IoError::Certificate => "Certificate",
        IoError::Handshake => "Handshake",
    };
}

fn server_thread(Sender tx) {
    let listener = match listen("127.0.0.1", 0) {
        Result::Ok(s) => s,
        Result::Err(_) => panic "listen",
    };
    let addr = match local_addr(listener) {
        Result::Ok(t) => t,
        Result::Err(_) => panic "addr",
    };
    let (_, port) = addr;
    match thread_send(tx, port) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "send port",
    };
    match await_readable(listener) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "await",
    };
    let conn = match accept(listener) {
        Result::Ok(s) => s,
        Result::Err(_) => panic "accept",
    };
    let s = match tls_server_enable(conn, {
        cert_pem: cert_pem(),
        key_pem: key_pem(),
        timeout_ms: 5000,
        client_ca_pem: "",
        alpn: "h2",
    }) {
        Result::Ok(v) => v,
        Result::Err(e) => panic "server enable " + io_err_tag(e),
    };
    match h2_serve_conn(s) {
        Result::Ok(_) => 0,
        Result::Err(_) => 0,
    };
}

fn main() {
    let pair = match channel() {
        Result::Ok(p) => p,
        Result::Err(_) => panic "channel",
    };
    let t = match spawn(server_thread, pair[0]) {
        Result::Ok(th) => th,
        Result::Err(_) => panic "spawn",
    };
    let port = match recv(pair[1]) {
        Result::Ok(p) => p,
        Result::Err(_) => panic "recv",
    };
    let tcp = match connect("127.0.0.1", port) {
        Result::Ok(s) => s,
        Result::Err(_) => panic "connect",
    };
    let s = match tls_client_enable(tcp, "localhost", {
        verify: false,
        ca_pem: Option::None,
        ca_path: Option::None,
        timeout_ms: 5000,
        alpn: "h2",
    }) {
        Result::Ok(v) => v,
        Result::Err(e) => panic "client enable " + io_err_tag(e),
    };
    let proto = match alpn_protocol(s) {
        Result::Ok(p) => p,
        Result::Err(_) => panic "alpn",
    };
    if proto != "h2" {
        panic "alpn not h2";
    }
    let url = "https://127.0.0.1:" + int_to_dec(port) + "/";
    let u = match parse_url(url) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "url",
    };
    match h2_get_over_h2(s, u) {
        Result::Ok(r) => {
            if r.status == 200 {
                if len(r.body) == 2 {
                    if r.body[0] == ("o" as byte) {
                        if r.body[1] == ("k" as byte) {
                            write_all(stdout(), to_bytes("ok"));
                        }
                    }
                }
            }
        },
        Result::Err(_) => panic "h2_get_over_h2",
    };
    match join(t) {
        Result::Ok(_) => 0,
        Result::Err(_) => 0,
    };
}