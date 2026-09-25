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

fn bytes_eq(Vec<byte> a, Vec<byte> b) -> int {
    if len(a) != len(b) {
        return 0;
    }
    let i = 0;
    while i < len(a) {
        if a[i] != b[i] {
            return 0;
        }
        i = i + 1;
    }
    return 1;
}

fn data_payload_len(Vec<byte> wire) -> int {
    let total = 0;
    let rest = wire;
    let guard = 0;
    while len(rest) >= 9 {
        if guard > 64 {
            return total;
        }
        let n = frame_wire_len(rest);
        if n == 0 {
            return total;
        }
        let f = match decode_frame(rest) {
            Result::Ok(v) => v,
            Result::Err(_) => {
                return total;
            },
        };
        if f.typ == frame_type_data() {
            total = total + len(f.payload);
        }
        let next: Vec<byte> = Vec::new();
        let i = n;
        while i < len(rest) {
            next.push(rest[i]);
            i = i + 1;
        }
        rest = next;
        guard = guard + 1;
    }
    return total;
}

fn count_type(Vec<byte> wire, int typ) -> int {
    let total = 0;
    let rest = wire;
    let guard = 0;
    while len(rest) >= 9 {
        if guard > 64 {
            return total;
        }
        let n = frame_wire_len(rest);
        if n == 0 {
            return total;
        }
        let f = match decode_frame(rest) {
            Result::Ok(v) => v,
            Result::Err(_) => {
                return total;
            },
        };
        if f.typ == typ {
            total = total + 1;
        }
        let next: Vec<byte> = Vec::new();
        let i = n;
        while i < len(rest) {
            next.push(rest[i]);
            i = i + 1;
        }
        rest = next;
        guard = guard + 1;
    }
    return total;
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

fn client_wire(H2Session cli) -> Vec<byte> {
    return cat_bytes(connection_preface(), cli.drain());
}

fn digits(string s) -> int {
    let b = to_bytes(s);
    let v = 0;
    let i = 0;
    while i < len(b) {
        v = v * 10 + ((b[i] as int) - (("0" as byte) as int));
        i = i + 1;
    }
    return v;
}

fn push_off() -> H2Settings {
    let st = H2Settings::new();
    st.add(2, 0);
    return st;
}

fn resp_of(H2Session cli, int sid) -> Response {
    let h = match cli.stream_headers(sid) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "headers",
    };
    let body = match cli.stream_body(sid) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "body",
    };
    let tr = match cli.stream_trailers(sid) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "trailers",
    };
    let r = Response::ok();
    let i = 0;
    let status = 200;
    while i < h.count() {
        if h.name_at(i) == ":status" {
            status = digits(h.value_at(i));
        } else {
            r.header(h.name_at(i), h.value_at(i));
        }
        i = i + 1;
    }
    r.status(status);
    r.body(body);
    let j = 0;
    while j < tr.count() {
        r.trailer(tr.name_at(j), tr.value_at(j));
        j = j + 1;
    }
    return r;
}

test("ping is acked with the same payload") {
    let sess = boot_session();
    let payload: Vec<byte> = Vec::new();
    let i = 0;
    while i < 8 {
        let n = i + 3;
        payload.push(n as byte);
        i = i + 1;
    }
    let ping = match ping_frame(payload, 0) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "ping",
    };
    match sess.feed(encode_frame(ping)) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "feed ping",
    };
    let out = sess.drain();
    let ack = match decode_frame(out) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "ack",
    };
    assert(ack.typ == frame_type_ping(), "ping")?;
    assert(ack.flags == flag_ack(), "ack flag")?;
    assert(bytes_eq(ack.payload, payload) == 1, "same payload")?;
}

test("zero window update is a connection error with goaway") {
    let sess = boot_session();
    let z: Vec<byte> = Vec::new();
    z.push(0 as byte);
    z.push(0 as byte);
    z.push(0 as byte);
    z.push(0 as byte);
    let f = H2Frame::new(frame_type_window_update(), 0, 0, z);
    let r = sess.feed(encode_frame(f));
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "zero increment")?;
    let out = sess.drain();
    let g = match decode_frame(out) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "goaway",
    };
    assert(g.typ == frame_type_goaway(), "goaway")?;
}

test("window update overflow is a connection error") {
    let sess = boot_session();
    let wu = match window_update_frame(0, h2_max_window()) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "wu",
    };
    let r = sess.feed(encode_frame(wu));
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "overflow")?;
    assert(count_type(sess.drain(), frame_type_goaway()) == 1, "goaway")?;
}

test("settings initial window max frame and max streams are applied") {
    let sess = boot_session();
    let st = H2Settings::new();
    st.add(settings_id_initial_window(), 1000);
    st.add(settings_id_max_frame_size(), 20000);
    st.add(settings_id_max_concurrent(), 7);
    st.add(settings_id_header_table_size(), 128);
    match sess.feed(encode_frame(settings_frame(st))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "settings",
    };
    assert(sess.peer_window == 1000, "window")?;
    assert(sess.peer_max_frame == 20000, "frame")?;
    assert(sess.peer_max_streams == 7, "streams")?;
    assert(sess.encoder.cap == 128, "encoder table")?;
    assert(sess.hpack.cap == 4096, "decoder stays")?;
    let bad = H2Settings::new();
    bad.add(settings_id_max_frame_size(), 100);
    let r = sess.feed(encode_frame(settings_frame(bad)));
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "tiny max frame")?;
}

test("stream send window stalls and resumes") {
    let cli = H2Session::client();
    let st = H2Settings::new();
    st.add(settings_id_initial_window(), 0);
    match cli.feed(encode_frame(settings_frame(st))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "settings",
    };
    let _ack = cli.drain();
    let u = match parse_url("http://127.0.0.1/post") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "url",
    };
    let body = to_bytes("abcdef");
    match cli.write_request(1, h2_request_headers(u, "POST", Headers::new()), body) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "write",
    };
    let first = cli.drain();
    assert(data_payload_len(first) == 0, "stalled")?;
    assert(count_type(first, frame_type_headers()) == 1, "headers out")?;
    let wu = match window_update_frame(1, 4) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "wu",
    };
    match cli.feed(encode_frame(wu)) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "resume",
    };
    let second = cli.drain();
    assert(data_payload_len(second) == 4, "four")?;
    let wu2 = match window_update_frame(1, 2) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "wu2",
    };
    match cli.feed(encode_frame(wu2)) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "resume2",
    };
    assert(data_payload_len(cli.drain()) == 2, "rest")?;
}

test("connection window stalls data then resumes") {
    let cli = H2Session::client();
    match cli.feed(encode_frame(H2Frame::new(frame_type_settings(), 0, 0, Vec::new()))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "settings",
    };
    let _ = cli.drain();
    cli.conn_send = 3;
    let u = match parse_url("http://127.0.0.1/c") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "url",
    };
    match cli.write_request(1, h2_request_headers(u, "POST", Headers::new()), to_bytes("0123456789")) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "write",
    };
    assert(data_payload_len(cli.drain()) == 3, "conn cap")?;
    let wu = match window_update_frame(0, 7) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "wu",
    };
    match cli.feed(encode_frame(wu)) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "conn resume",
    };
    assert(data_payload_len(cli.drain()) == 7, "rest")?;
}

test("rst stream ends only that stream") {
    let sess = boot_session();
    let h = Headers::new();
    h.add(":method", "GET");
    h.add(":path", "/a");
    let h3 = Headers::new();
    h3.add(":method", "GET");
    h3.add(":path", "/b");
    match sess.feed(encode_frame(headers_frame(1, h, 0))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "h1",
    };
    match sess.feed(encode_frame(headers_frame(3, h3, 0))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "h3",
    };
    match sess.feed(encode_frame(rst_stream_frame(1, 8))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "rst",
    };
    let rst = match sess.stream_reset(1) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "reset flag",
    };
    assert(rst == 1, "reset")?;
    match sess.feed(encode_frame(data_frame(3, to_bytes("zz"), 1))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "other stream",
    };
    let body = match sess.stream_body(3) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "body",
    };
    assert(bytes_eq(body, to_bytes("zz")) == 1, "zz")?;
    let still = match sess.stream_reset(3) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "r3",
    };
    assert(still == 0, "stream 3 open")?;
}

test("goaway refuses new streams and lets earlier ones finish") {
    let sess = boot_session();
    let h = Headers::new();
    h.add(":method", "GET");
    h.add(":path", "/a");
    match sess.feed(encode_frame(headers_frame(1, h, 0))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "h1",
    };
    match sess.feed(encode_frame(goaway_frame(1, 0))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "goaway",
    };
    assert(sess.goaway_received() == 1, "seen")?;
    assert(sess.goaway_last_stream() == 1, "last")?;
    let h3 = Headers::new();
    h3.add(":method", "GET");
    h3.add(":path", "/later");
    match sess.feed(encode_frame(headers_frame(3, h3, 1))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "refused quietly",
    };
    assert(sess.stream_count() == 1, "no stream 3")?;
    match sess.feed(encode_frame(data_frame(1, to_bytes("go"), 1))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "finish 1",
    };
    let body = match sess.stream_body(1) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "body",
    };
    assert(bytes_eq(body, to_bytes("go")) == 1, "go")?;
}

test("handler sees post body trailers and interleaved gets") {
    let srv = H2Session::new();
    match srv.queue_local_settings(push_off()) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "arm",
    };
    let srv_settings = srv.drain();
    let cli = H2Session::client();
    match cli.queue_local_settings(push_off()) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "cli arm",
    };
    let a = match parse_url("http://127.0.0.1/a") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "a",
    };
    let b = match parse_url("http://127.0.0.1/b") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "b",
    };
    let post = match parse_url("http://127.0.0.1/echo") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "post",
    };
    let extra = Headers::new();
    extra.add("x-trace", "same-value");
    match cli.write_request(1, h2_request_headers(a, "GET", extra), Vec::new()) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "get a",
    };
    match cli.write_request(3, h2_request_headers(b, "GET", extra), Vec::new()) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "get b",
    };
    match cli.write_request(5, h2_request_headers(post, "POST", extra), to_bytes("xyzzy")) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "post",
    };
    assert(cli.encoder.size > 0, "encoder indexed")?;
    let req = client_wire(cli);
    match cli.feed(srv_settings) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "cli settings",
    };
    let cli_ack = cli.drain();
    match srv.feed(req) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "srv req",
    };
    match srv.feed(cli_ack) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "srv ack",
    };
    assert(srv.stream_count() == 3, "three")?;
    let h3 = match srv.stream_headers(3) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "h3",
    };
    assert(h3.value_at(0) == "GET", "get b")?;
    let posted = match srv.stream_body(5) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "post body",
    };
    assert(bytes_eq(posted, to_bytes("xyzzy")) == 1, "xyzzy")?;
    let done: Vec<int> = Vec::new();
    match h2_dispatch_ready(srv, new AppHandler(), done) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "dispatch",
    };
    match cli.feed(srv.drain()) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "cli resp",
    };
    let r1 = resp_of(cli, 1);
    let r3 = resp_of(cli, 3);
    let r5 = resp_of(cli, 5);
    assert(r1.status == 200, "200")?;
    assert(bytes_eq(r1.body, to_bytes("alpha")) == 1, "alpha")?;
    assert(header_get(r1, "x-path") == "/a", "path a")?;
    assert(r3.status == 204, "204")?;
    assert(bytes_eq(r3.body, to_bytes("bee")) == 1, "bee")?;
    assert(r5.status == 201, "201")?;
    assert(bytes_eq(r5.body, to_bytes("xyzzy")) == 1, "echo")?;
    assert(header_get(r5, "x-echo") == "/echo", "echo path")?;
    assert(trailer_get(r5, "x-trail") == "posted", "trailer")?;
}

test("header block over max frame is split and reassembled") {
    let h = Headers::new();
    h.add(":method", "GET");
    h.add(":path", "/continuation-path");
    h.add("x-trace", "www.example.com");
    let wire = headers_frames(1, h, 1, 8);
    assert(count_type(wire, frame_type_headers()) == 1, "headers")?;
    assert(count_type(wire, 9) >= 1, "continuation")?;
    let sess = boot_session();
    match sess.feed(wire) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "feed split",
    };
    let got = match sess.stream_headers(1) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "headers",
    };
    assert(got.value_at(1) == "/continuation-path", "path")?;
    assert(got.value_at(2) == "www.example.com", "trace")?;
}

test("recv window overflow is a connection error") {
    let sess = boot_session();
    let h = Headers::new();
    h.add(":method", "POST");
    h.add(":path", "/");
    match sess.feed(encode_frame(headers_frame(1, h, 0))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "headers",
    };
    sess.conn_recv = 2;
    let r = sess.feed(encode_frame(data_frame(1, to_bytes("abcd"), 1)));
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "overflow data")?;
    assert(count_type(sess.drain(), frame_type_goaway()) == 1, "goaway")?;
}

test("peer max concurrent streams refuses another local stream") {
    let cli = H2Session::client();
    let st = H2Settings::new();
    st.add(settings_id_max_concurrent(), 1);
    match cli.feed(encode_frame(settings_frame(st))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "settings",
    };
    let _ = cli.drain();
    let u = match parse_url("http://127.0.0.1/a") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "url",
    };
    match cli.write_request(1, h2_request_headers(u, "GET", Headers::new()), Vec::new()) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "first",
    };
    let r = cli.write_request(3, h2_request_headers(u, "GET", Headers::new()), Vec::new());
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "second refused")?;
}

test("closed stream frees a concurrency slot") {
    let cli = H2Session::client();
    let st = H2Settings::new();
    st.add(settings_id_max_concurrent(), 1);
    match cli.feed(encode_frame(settings_frame(st))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "settings",
    };
    let _ = cli.drain();
    let u = match parse_url("http://127.0.0.1/a") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "url",
    };
    match cli.write_request(1, h2_request_headers(u, "GET", Headers::new()), Vec::new()) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "first",
    };
    let _ = cli.drain();
    let rh = Headers::new();
    rh.add(":status", "200");
    match cli.feed(encode_frame(headers_frame(1, rh, 1))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "response",
    };
    match cli.write_request(3, h2_request_headers(u, "GET", Headers::new()), Vec::new()) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "third after close",
    };
}

test("trailer block is encoded when it is flushed") {
    let enc = boot_session();
    let req = Headers::new();
    req.add(":method", "GET");
    req.add(":path", "/");
    match enc.feed(encode_frame(headers_frame(1, req, 1))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "s1",
    };
    match enc.feed(encode_frame(headers_frame(3, req, 1))) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "s3",
    };
    let _ = enc.drain();
    let idx = enc.find_id(1);
    enc.send_win[idx] = 1;
    let trails = Headers::new();
    trails.add("x-trace", "vv");
    let fields = Headers::new();
    fields.add("x-trace", "vv");
    let nobody: Vec<byte> = Vec::new();
    match enc.queue_response(1, 200, Headers::new(), to_bytes("abcd"), trails) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "resp1",
    };
    match enc.queue_response(3, 200, fields, nobody, Headers::new()) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "resp3",
    };
    let dec = boot_session();
    match dec.feed(enc.drain()) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "mid decode",
    };
    let wu = match window_update_frame(1, 10) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "wu",
    };
    match enc.feed(encode_frame(wu)) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "resume",
    };
    match dec.feed(enc.drain()) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "rest decode",
    };
    let h3 = match dec.stream_headers(3) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "h3",
    };
    assert(h3.value_at(1) == "vv", "stream 3 trace")?;
    let tr = match dec.stream_trailers(1) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "trailers",
    };
    assert(tr.value_at(0) == "vv", "trailer trace")?;
    let body = match dec.stream_body(1) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "body",
    };
    assert(bytes_eq(body, to_bytes("abcd")) == 1, "abcd")?;
}
