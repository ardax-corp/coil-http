// COI-408: Client::get against a separate process that delays the response.
use conv::{int_to_dec};
use string::{to_bytes};
use io::{stdout};
use io::sync::{write_all};
use http::client::Client;

fn main() {
    let url = "http://127.0.0.1:" + int_to_dec(18765) + "/";
    let c = Client::new();
    c.no_pool();
    match c.get(url) {
        Result::Ok(r) => {
            if r.status != 200 {
                panic "status";
            }
            write_all(stdout(), to_bytes("ok"));
        },
        Result::Err(_) => {
            panic "get failed";
        },
    };
}
