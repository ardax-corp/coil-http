// COI-408: Client::h2_get against a separate process that delays SETTINGS.
use conv::{int_to_dec};
use string::{to_bytes};
use io::{stdout};
use io::sync::{write_all};
use http::client::Client;

fn main() {
    let url = "http://127.0.0.1:" + int_to_dec(18766) + "/";
    let c = Client::new();
    match c.h2_get(url) {
        Result::Ok(r) => {
            if r.status != 200 {
                panic "status";
            }
            write_all(stdout(), to_bytes("ok"));
        },
        Result::Err(_) => {
            panic "h2_get failed";
        },
    };
}
