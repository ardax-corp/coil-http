// HTTP/2 flow control, settings, ping, reset, goaway, bodies, trailers, handler dispatch.
use string::{to_bytes};
use http::url::{Headers, parse_url};
use http::h1::IncomingRequest;
use http::response::{Response, header_get, trailer_get};
use http::h2::{
    H2Frame,
    H2Settings,
    connection_preface,
    data_frame,
    decode_frame,
    encode_frame,
    flag_ack,
    frame_type_data,
    frame_type_goaway,
    frame_type_headers,
    frame_type_ping,
    frame_type_rst_stream,
    frame_type_settings,
    frame_type_window_update,
    frame_wire_len,
    goaway_frame,
    headers_frame,
    headers_frames,
    h2_max_window,
    h2_request_headers,
    rst_stream_frame,
    settings_frame,
    settings_id_header_table_size,
    settings_id_initial_window,
    settings_id_max_concurrent,
    settings_id_max_frame_size,
    window_update_frame,
    ping_frame,
};
use http::h2_session::{H2Session};
use http::server::{HttpHandler, h2_dispatch_ready};

fn cat_bytes(Vec<byte> a, Vec<byte> b) -> Vec<byte> {
    let out: Vec<byte> = Vec::new();
    let i = 0;
    while i < len(a) {
        out.push(a[i]);
        i = i + 1;
    }
    let j = 0;
    while j < len(b) {
        out.push(b[j]);
        j = j + 1;
    }
    return out;
}

fn boot_session() -> H2Session {
    let sess = H2Session::new();
    let wire = cat_bytes(connection_preface(), encode_frame(H2Frame::new(frame_type_settings(), 0, 0, Vec::new())));
    match sess.feed(wire) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "boot",
    };
    let _ = sess.drain();
    return sess;
}

class AppHandler {}

impl HttpHandler for AppHandler {
    fn handle(AppHandler self, IncomingRequest req) -> Response {
        let r = Response::ok();
        if req.method_val() == "POST" {
            r.status(201);
            r.header("x-echo", req.path_val());
            r.body(req.body_val());
            r.trailer("x-trail", "posted");
            return r;
        }
        if req.path_val() == "/b" {
            r.status(204);
            r.body(to_bytes("bee"));
            return r;
        }
        r.status(200);
        r.header("x-path", req.path_val());
        r.body(to_bytes("alpha"));
        return r;
    }
}
