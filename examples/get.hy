// HTTP GET example (requires a server at the URL).
use http::client::Client;
use io::{stdout};
use io::sync::{write_all};
use string::{format, to_bytes};

fn main() {
    let c = Client::new();
    c.no_pool();
    match c.get("http://127.0.0.1:41250/") {
        Result::Ok(r) => {
            write_all(stdout(), to_bytes(format("status=%i", r.status)));
        },
        Result::Err(_) => {
            panic "get failed";
        },
    };
}
