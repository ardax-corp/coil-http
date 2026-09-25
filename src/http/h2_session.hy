// In-memory HTTP/2 connection: preface, frames, flow control, no sockets.
// Socket loops call this session and write whatever `drain` queues.
use conv::{int_to_dec};
use io::{Stream};
use io::net::tcp::connect as tcp_connect;
use io::sync::{write_all};
use tls::client::{enable as tls_enable, ClientOpts};
use tls::alpn_protocol;
use http::url::{
    HttpError,
    Headers,
    Url,
    bytes_slice,
    http_err_bad_response,
    http_err_bad_url,
    http_err_io,
    http_fail_stream,
    http_fail_unit,
    parse_url,
};
use http::hpack::{HpackTable, decode_header_block_with, encode_header_block_with, hpack_table_resize};
use http::response::{Response};
use http::h2::{
    H2Frame,
    H2Settings,
    connection_preface,
    data_frame,
    decode_frame,
    decode_goaway_payload,
    decode_push_promise_payload,
    decode_rst_payload,
    decode_settings_payload,
    decode_window_update_payload,
    default_max_frame_payload,
    encode_frame,
    encode_headers_block_frames,
    frame_type_continuation,
    frame_type_data,
    frame_type_goaway,
    frame_type_headers,
    frame_type_ping,
    frame_type_priority,
    frame_type_push_promise,
    frame_type_rst_stream,
    frame_type_settings,
    frame_type_window_update,
    frame_wire_len,
    goaway_frame,
    h2_alpn_is_h2,
    h2_client_alpn,
    h2_close,
    h2_end_headers_set,
    h2_err_flow_control,
    h2_err_frame_size,
    h2_err_protocol,
    h2_err_refused_stream,
    h2_http11_exchange,
    h2_max_frame_setting,
    h2_max_window,
    h2_read_frame,
    h2_request_headers,
    h2_status_from_headers,
    headers_from_frame_with,
    ping_frame,
    push_promise_frame,
    rst_stream_frame,
    settings_ack_frame,
    window_update_frame,
    settings_frame,
    settings_id_enable_push,
    settings_id_header_table_size,
    settings_id_initial_window,
    settings_id_max_concurrent,
    settings_id_max_frame_size,
};

fn h2_stream_cap() -> int {
    return 1073741823;
}

fn h2_append_bytes(Vec<byte> out, Vec<byte> extra) {
    let i = 0;
    while i < len(extra) {
        out.push(extra[i]);
        i = i + 1;
    }
}

/// One HTTP/2 connection (client or server) over a byte buffer.
class H2Session {
    preface_done: int,
    settings_done: int,
    buf: Vec<byte>,
    outgoing: Vec<byte>,
    ids: Vec<int>,
    ended: Vec<int>,
    hnum: Vec<int>,
    names: Vec<string>,
    values: Vec<string>,
    blob: Vec<byte>,
    bstart: Vec<int>,
    blen: Vec<int>,
    hpack: HpackTable,
    cont_on: int,
    cont_sid: int,
    cont_end_stream: int,
    cont_kind: int,
    cont_promised: int,
    cont_buf: Vec<byte>,
    push_ids: Vec<int>,
    push_hnum: Vec<int>,
    push_names: Vec<string>,
    push_values: Vec<string>,
    role: int,
    conn_send: int,
    conn_recv: int,
    peer_window: int,
    local_window: int,
    peer_max_frame: int,
    local_max_frame: int,
    peer_max_streams: int,
    local_max_streams: int,
    local_enable_push: int,
    remote_streams: int,
    local_streams: int,
    goaway_recv: int,
    goaway_last: int,
    goaway_sent: int,
    last_peer_stream: int,
    send_win: Vec<int>,
    recv_win: Vec<int>,
    reset: Vec<int>,
    phase: Vec<int>,
    pblob: Vec<byte>,
    pstart: Vec<int>,
    plen: Vec<int>,
    pend_es: Vec<int>,
    tnum: Vec<int>,
    tnames: Vec<string>,
    tvalues: Vec<string>,
    encoder: HpackTable,
    conn_err: int,
    tb_on: Vec<int>,
    ot_num: Vec<int>,
    ot_names: Vec<string>,
    ot_values: Vec<string>,
    local_es: Vec<int>,
    conc_held: Vec<int>,
    conc_remote: Vec<int>,
}

impl H2Session {
    pub static fn open(int role, int preface_done) -> H2Session {
        let buf: Vec<byte> = Vec::new();
        let outgoing: Vec<byte> = Vec::new();
        let ids: Vec<int> = Vec::new();
        let ended: Vec<int> = Vec::new();
        let hnum: Vec<int> = Vec::new();
        let names: Vec<string> = Vec::new();
        let values: Vec<string> = Vec::new();
        let blob: Vec<byte> = Vec::new();
        let bstart: Vec<int> = Vec::new();
        let blen: Vec<int> = Vec::new();
        let cont_buf: Vec<byte> = Vec::new();
        let push_ids: Vec<int> = Vec::new();
        let push_hnum: Vec<int> = Vec::new();
        let push_names: Vec<string> = Vec::new();
        let push_values: Vec<string> = Vec::new();
        let send_win: Vec<int> = Vec::new();
        let recv_win: Vec<int> = Vec::new();
        let reset: Vec<int> = Vec::new();
        let phase: Vec<int> = Vec::new();
        let pblob: Vec<byte> = Vec::new();
        let pstart: Vec<int> = Vec::new();
        let plen: Vec<int> = Vec::new();
        let pend_es: Vec<int> = Vec::new();
        let tnum: Vec<int> = Vec::new();
        let tnames: Vec<string> = Vec::new();
        let tvalues: Vec<string> = Vec::new();
        let tb_on: Vec<int> = Vec::new();
        let ot_num: Vec<int> = Vec::new();
        let ot_names: Vec<string> = Vec::new();
        let ot_values: Vec<string> = Vec::new();
        let local_es: Vec<int> = Vec::new();
        let conc_held: Vec<int> = Vec::new();
        let conc_remote: Vec<int> = Vec::new();
        let win = 65535;
        let frame_max = default_max_frame_payload();
        let cap = 1073741823;
        return new H2Session(
            preface_done,
            0,
            buf,
            outgoing,
            ids,
            ended,
            hnum,
            names,
            values,
            blob,
            bstart,
            blen,
            HpackTable::new(4096),
            0,
            0,
            0,
            0,
            0,
            cont_buf,
            push_ids,
            push_hnum,
            push_names,
            push_values,
            role,
            win,
            win,
            win,
            win,
            frame_max,
            frame_max,
            cap,
            cap,
            1,
            0,
            0,
            0,
            0,
            0,
            0,
            send_win,
            recv_win,
            reset,
            phase,
            pblob,
            pstart,
            plen,
            pend_es,
            tnum,
            tnames,
            tvalues,
            HpackTable::new(4096),
            0,
            tb_on,
            ot_num,
            ot_names,
            ot_values,
            local_es,
            conc_held,
            conc_remote
        );
    }

    /// Server role: expect the client connection preface.
    pub static fn new() -> H2Session {
        return H2Session::open(0, 0);
    }

    /// Client role: the peer does not send a connection preface.
    pub static fn client() -> H2Session {
        return H2Session::open(1, 1);
    }

    pub fn find_id(int sid) -> int {
        let i = 0;
        let n = len(self.ids);
        while i < n {
            if self.ids[i] == sid {
                return i;
            }
            i = i + 1;
        }
        return 999999;
    }

    pub fn queue_frame(H2Frame f) {
        self.queue_bytes(encode_frame(f));
    }

    pub fn queue_bytes(Vec<byte> wire) {
        let i = 0;
        while i < len(wire) {
            self.outgoing.push(wire[i]);
            i = i + 1;
        }
    }

    pub fn fail_conn(int code) -> Result<(), HttpError> {
        if self.goaway_sent == 0 {
            self.goaway_sent = 1;
            self.conn_err = 1;
            self.queue_frame(goaway_frame(self.last_peer_stream, code));
        }
        self.conn_err = 1;
        http_err_bad_response()?;
        return ();
    }

    pub fn try_preface() -> Result<(), HttpError> {
        let want = connection_preface();
        let have = len(self.buf);
        let check = have;
        if check > 24 {
            check = 24;
        }
        let i = 0;
        while i < check {
            if self.buf[i] != want[i] {
                http_err_bad_response()?;
            }
            i = i + 1;
        }
        if have < 24 {
            return ();
        }
        self.preface_done = 1;
        self.buf = bytes_slice(self.buf, 24, have);
        return ();
    }

    fn adjust_windows(Vec<int> wins, int delta) -> Result<(), HttpError> {
        let max = h2_max_window();
        let i = 0;
        let n = len(wins);
        while i < n {
            if delta > 0 {
                if wins[i] > max - delta {
                    return self.fail_conn(h2_err_flow_control())?;
                }
            }
            wins[i] = wins[i] + delta;
            i = i + 1;
        }
        return ();
    }

    fn apply_one_setting(int id, int value, int peer) -> Result<(), HttpError> {
        if id == settings_id_header_table_size() {
            if peer == 1 {
                hpack_table_resize(self.encoder, value);
            } else {
                hpack_table_resize(self.hpack, value);
            }
            return ();
        }
        if id == settings_id_enable_push() {
            if value != 0 {
                if value != 1 {
                    return self.fail_conn(h2_err_protocol())?;
                }
            }
            if peer == 0 {
                self.local_enable_push = value;
            }
            return ();
        }
        if id == settings_id_max_concurrent() {
            if peer == 1 {
                self.peer_max_streams = value;
            } else {
                self.local_max_streams = value;
            }
            return ();
        }
        if id == settings_id_initial_window() {
            if value < 0 {
                return self.fail_conn(h2_err_flow_control())?;
            }
            if value > h2_max_window() {
                return self.fail_conn(h2_err_flow_control())?;
            }
            if peer == 1 {
                let delta = value - self.peer_window;
                self.peer_window = value;
                self.adjust_windows(self.send_win, delta)?;
                if delta > 0 {
                    self.flush_all();
                }
            } else {
                let delta = value - self.local_window;
                self.local_window = value;
                self.adjust_windows(self.recv_win, delta)?;
            }
            return ();
        }
        if id == settings_id_max_frame_size() {
            if value < default_max_frame_payload() {
                return self.fail_conn(h2_err_protocol())?;
            }
            if value > h2_max_frame_setting() {
                return self.fail_conn(h2_err_protocol())?;
            }
            if peer == 1 {
                self.peer_max_frame = value;
            } else {
                self.local_max_frame = value;
            }
            return ();
        }
        return ();
    }

    fn apply_settings_list(H2Settings s, int peer) -> Result<(), HttpError> {
        let i = 0;
        let n = s.count();
        while i < n {
            self.apply_one_setting(s.ids[i], s.values[i], peer)?;
            i = i + 1;
        }
        return ();
    }

    /// Queue a SETTINGS frame and apply it to the local side.
    pub fn queue_local_settings(H2Settings s) -> Result<(), HttpError> {
        self.apply_settings_list(s, 0)?;
        self.queue_frame(settings_frame(s));
        return ();
    }

    pub fn on_settings(H2Frame f) -> Result<(), HttpError> {
        if f.stream_id != 0 {
            return self.fail_conn(h2_err_protocol())?;
        }
        if f.flags % 2 == 1 {
            if len(f.payload) != 0 {
                return self.fail_conn(h2_err_frame_size())?;
            }
            self.settings_done = 1;
            return ();
        }
        let s = decode_settings_payload(f.payload)?;
        self.apply_settings_list(s, 1)?;
        self.settings_done = 1;
        self.queue_frame(settings_ack_frame());
        return ();
    }

    pub fn require_client_sid(int sid) -> Result<(), HttpError> {
        if sid == 0 {
            return self.fail_conn(h2_err_protocol())?;
        }
        if sid % 2 == 0 {
            return self.fail_conn(h2_err_protocol())?;
        }
        return ();
    }

    fn push_slot(int sid, int end_stream, int phase, int hnum, int from_peer) {
        self.ids.push(sid);
        self.ended.push(end_stream);
        self.hnum.push(hnum);
        self.bstart.push(len(self.blob));
        self.blen.push(0);
        self.send_win.push(self.peer_window);
        self.recv_win.push(self.local_window);
        self.reset.push(0);
        self.phase.push(phase);
        self.pstart.push(0);
        self.plen.push(0);
        self.pend_es.push(0);
        self.tnum.push(0);
        self.tb_on.push(0);
        self.ot_num.push(0);
        self.local_es.push(0);
        self.conc_held.push(1);
        self.conc_remote.push(from_peer);
        if from_peer == 1 {
            if sid > self.last_peer_stream {
                self.last_peer_stream = sid;
            }
        }
    }

    fn release_conc(int idx) {
        if self.conc_held[idx] == 0 {
            return;
        }
        self.conc_held[idx] = 0;
        if self.conc_remote[idx] == 1 {
            if self.remote_streams > 0 {
                self.remote_streams = self.remote_streams - 1;
            }
        } else {
            if self.local_streams > 0 {
                self.local_streams = self.local_streams - 1;
            }
        }
    }

    /// Drop the concurrency slot after RST, or after both directions have ended.
    fn note_closed(int idx) {
        if self.reset[idx] == 1 {
            self.release_conc(idx);
            return;
        }
        if self.ended[idx] == 1 {
            if self.local_es[idx] == 1 {
                self.release_conc(idx);
            }
        }
    }

    fn copy_header_range(Vec<string> src_n, Vec<string> src_v, Vec<int> counts, int idx, Vec<string> nn, Vec<string> vv) {
        let skip = 0;
        let j = 0;
        while j < idx {
            skip = skip + counts[j];
            j = j + 1;
        }
        let k = 0;
        let n = counts[idx];
        while k < n {
            nn.push(src_n[skip + k]);
            vv.push(src_v[skip + k]);
            k = k + 1;
        }
    }

    fn fill_headers(int idx, Headers h) {
        let nn: Vec<string> = Vec::new();
        let vv: Vec<string> = Vec::new();
        let i = 0;
        let ns = len(self.ids);
        while i < ns {
            if i == idx {
                let k = 0;
                while k < h.count() {
                    nn.push(h.name_at(k));
                    vv.push(h.value_at(k));
                    k = k + 1;
                }
            } else {
                self.copy_header_range(self.names, self.values, self.hnum, i, nn, vv);
            }
            i = i + 1;
        }
        self.hnum[idx] = h.count();
        self.names = nn;
        self.values = vv;
    }

    fn fill_trailers(int idx, Headers h) {
        let nn: Vec<string> = Vec::new();
        let vv: Vec<string> = Vec::new();
        let i = 0;
        let ns = len(self.ids);
        while i < ns {
            if i == idx {
                let k = 0;
                while k < h.count() {
                    nn.push(h.name_at(k));
                    vv.push(h.value_at(k));
                    k = k + 1;
                }
            } else {
                self.copy_header_range(self.tnames, self.tvalues, self.tnum, i, nn, vv);
            }
            i = i + 1;
        }
        self.tnum[idx] = h.count();
        self.tnames = nn;
        self.tvalues = vv;
    }

    pub fn store_headers(int sid, int end_stream, Headers h) -> Result<(), HttpError> {
        let idx = self.find_id(sid);
        if idx != 999999 {
            return self.fail_conn(h2_err_protocol())?;
        }
        let n = h.count();
        self.push_slot(sid, end_stream, 1, n, 1);
        let i = 0;
        while i < n {
            self.names.push(h.name_at(i));
            self.values.push(h.value_at(i));
            i = i + 1;
        }
        return ();
    }

    pub fn accept_headers(int sid, int end_stream, Headers h) -> Result<(), HttpError> {
        if self.stream_is_reset(sid) == 1 {
            return ();
        }
        let idx = self.find_id(sid);
        if idx == 999999 {
            if self.goaway_recv == 1 {
                if sid > self.goaway_last {
                    return ();
                }
            }
            if self.goaway_sent == 1 {
                if sid > self.last_peer_stream {
                    return ();
                }
            }
            if self.remote_streams >= self.local_max_streams {
                self.remote_streams = self.remote_streams + 1;
                self.push_slot(sid, 1, 1, 0, 1);
                let idx2 = self.find_id(sid);
                self.reset[idx2] = 1;
                self.release_conc(idx2);
                self.queue_frame(rst_stream_frame(sid, h2_err_refused_stream()));
                return ();
            }
            self.remote_streams = self.remote_streams + 1;
            return self.store_headers(sid, end_stream, h)?;
        }
        if self.phase[idx] == 0 {
            self.fill_headers(idx, h);
            self.phase[idx] = 1;
            if end_stream != 0 {
                self.ended[idx] = 1;
            }
            self.note_closed(idx);
            return ();
        }
        if self.ended[idx] == 1 {
            return self.fail_conn(h2_err_protocol())?;
        }
        if end_stream == 0 {
            return self.fail_conn(h2_err_protocol())?;
        }
        self.fill_trailers(idx, h);
        self.phase[idx] = 2;
        self.ended[idx] = 1;
        self.note_closed(idx);
        return ();
    }

    pub fn finish_headers(int sid, int end_stream, Vec<byte> block) -> Result<(), HttpError> {
        self.require_client_sid(sid)?;
        let h = decode_header_block_with(block, self.hpack)?;
        return self.accept_headers(sid, end_stream, h)?;
    }

    pub fn finish_push(int associated, int promised, Vec<byte> block) -> Result<(), HttpError> {
        self.require_client_sid(associated)?;
        if self.find_id(associated) == 999999 {
            return self.fail_conn(h2_err_protocol())?;
        }
        if promised == 0 {
            return self.fail_conn(h2_err_protocol())?;
        }
        if promised % 2 == 1 {
            return self.fail_conn(h2_err_protocol())?;
        }
        let h = decode_header_block_with(block, self.hpack)?;
        self.push_ids.push(promised);
        let n = h.count();
        self.push_hnum.push(n);
        let i = 0;
        while i < n {
            self.push_names.push(h.name_at(i));
            self.push_values.push(h.value_at(i));
            i = i + 1;
        }
        return ();
    }

    pub fn clear_cont() {
        self.cont_on = 0;
        self.cont_sid = 0;
        self.cont_end_stream = 0;
        self.cont_kind = 0;
        self.cont_promised = 0;
        let empty: Vec<byte> = Vec::new();
        self.cont_buf = empty;
    }

    fn stream_is_reset(int sid) -> int {
        let idx = self.find_id(sid);
        if idx == 999999 {
            return 0;
        }
        return self.reset[idx];
    }

    pub fn on_headers(H2Frame f) -> Result<(), HttpError> {
        self.require_client_sid(f.stream_id)?;
        if self.stream_is_reset(f.stream_id) == 1 {
            return ();
        }
        if h2_end_headers_set(f.flags) == 1 {
            let h = headers_from_frame_with(f, self.hpack)?;
            return self.accept_headers(f.stream_id, f.flags % 2, h)?;
        }
        self.cont_on = 1;
        self.cont_sid = f.stream_id;
        self.cont_end_stream = f.flags % 2;
        self.cont_kind = 1;
        self.cont_promised = 0;
        self.cont_buf = bytes_slice(f.payload, 0, len(f.payload));
        return ();
    }

    pub fn on_push_promise(H2Frame f) -> Result<(), HttpError> {
        if self.local_enable_push == 0 {
            return self.fail_conn(h2_err_protocol())?;
        }
        self.require_client_sid(f.stream_id)?;
        if self.find_id(f.stream_id) == 999999 {
            return self.fail_conn(h2_err_protocol())?;
        }
        let p = decode_push_promise_payload(f.payload)?;
        if h2_end_headers_set(f.flags) == 1 {
            return self.finish_push(f.stream_id, p.promised_id, p.block)?;
        }
        self.cont_on = 1;
        self.cont_sid = f.stream_id;
        self.cont_end_stream = 0;
        self.cont_kind = 2;
        self.cont_promised = p.promised_id;
        self.cont_buf = bytes_slice(p.block, 0, len(p.block));
        return ();
    }

    pub fn on_continuation(H2Frame f) -> Result<(), HttpError> {
        if self.cont_on == 0 {
            return self.fail_conn(h2_err_protocol())?;
        }
        if f.stream_id != self.cont_sid {
            return self.fail_conn(h2_err_protocol())?;
        }
        let i = 0;
        while i < len(f.payload) {
            self.cont_buf.push(f.payload[i]);
            i = i + 1;
        }
        if h2_end_headers_set(f.flags) == 0 {
            return ();
        }
        let sid = self.cont_sid;
        let es = self.cont_end_stream;
        let kind = self.cont_kind;
        let promised = self.cont_promised;
        let block = self.cont_buf;
        self.clear_cont();
        if kind == 2 {
            return self.finish_push(sid, promised, block)?;
        }
        return self.finish_headers(sid, es, block)?;
    }

    pub fn queue_push(int associated, int promised, string method, string path, string authority) {
        let h = Headers::new();
        h.add(":method", method);
        h.add(":path", path);
        h.add(":authority", authority);
        self.queue_frame(push_promise_frame(associated, promised, h));
    }

    pub fn append_body(int idx, Vec<byte> payload) {
        let newb: Vec<byte> = Vec::new();
        let starts: Vec<int> = Vec::new();
        let i = 0;
        let n = len(self.ids);
        while i < n {
            starts.push(len(newb));
            let off = self.bstart[i];
            let k = 0;
            let lim = self.blen[i];
            while k < lim {
                newb.push(self.blob[off + k]);
                k = k + 1;
            }
            if i == idx {
                let p = 0;
                while p < len(payload) {
                    newb.push(payload[p]);
                    p = p + 1;
                }
            }
            i = i + 1;
        }
        let j = 0;
        while j < n {
            self.bstart[j] = starts[j];
            j = j + 1;
        }
        self.blen[idx] = self.blen[idx] + len(payload);
        self.blob = newb;
    }

    fn note_recv(int idx, int n) -> Result<(), HttpError> {
        if n > self.recv_win[idx] {
            return self.fail_conn(h2_err_flow_control())?;
        }
        if n > self.conn_recv {
            return self.fail_conn(h2_err_flow_control())?;
        }
        self.recv_win[idx] = self.recv_win[idx] - n;
        self.conn_recv = self.conn_recv - n;
        if n > 0 {
            self.recv_win[idx] = self.recv_win[idx] + n;
            self.conn_recv = self.conn_recv + n;
            let wu_s = window_update_frame(self.ids[idx], n)?;
            self.queue_frame(wu_s);
            let wu_c = window_update_frame(0, n)?;
            self.queue_frame(wu_c);
        }
        return ();
    }

    pub fn on_data(H2Frame f) -> Result<(), HttpError> {
        self.require_client_sid(f.stream_id)?;
        let idx = self.find_id(f.stream_id);
        if idx == 999999 {
            return self.fail_conn(h2_err_protocol())?;
        }
        if self.reset[idx] == 1 {
            return ();
        }
        if self.ended[idx] == 1 {
            return self.fail_conn(h2_err_protocol())?;
        }
        self.note_recv(idx, len(f.payload))?;
        self.append_body(idx, f.payload);
        if f.flags % 2 == 1 {
            self.ended[idx] = 1;
        }
        self.note_closed(idx);
        return ();
    }

    fn on_ping(H2Frame f) -> Result<(), HttpError> {
        if f.stream_id != 0 {
            return self.fail_conn(h2_err_protocol())?;
        }
        if len(f.payload) != 8 {
            return self.fail_conn(h2_err_frame_size())?;
        }
        if f.flags % 2 == 0 {
            let ack = ping_frame(f.payload, 1)?;
            self.queue_frame(ack);
        }
        return ();
    }

    fn on_rst(H2Frame f) -> Result<(), HttpError> {
        if f.stream_id == 0 {
            return self.fail_conn(h2_err_protocol())?;
        }
        match decode_rst_payload(f.payload) {
            Result::Ok(_) => 0,
            Result::Err(_) => {
                return self.fail_conn(h2_err_frame_size())?;
            },
        };
        let idx = self.find_id(f.stream_id);
        if idx == 999999 {
            return self.fail_conn(h2_err_protocol())?;
        }
        self.reset[idx] = 1;
        self.ended[idx] = 1;
        self.release_conc(idx);
        return ();
    }

    fn on_window(H2Frame f) -> Result<(), HttpError> {
        if len(f.payload) != 4 {
            return self.fail_conn(h2_err_frame_size())?;
        }
        let inc = match decode_window_update_payload(f.payload) {
            Result::Ok(v) => v,
            Result::Err(_) => {
                self.fail_conn(h2_err_protocol())?;
                0
            },
        };
        return self.add_send_window(f.stream_id, inc)?;
    }

    fn add_send_window(int sid, int inc) -> Result<(), HttpError> {
        let max = h2_max_window();
        if sid == 0 {
            if self.conn_send > max - inc {
                return self.fail_conn(h2_err_flow_control())?;
            }
            self.conn_send = self.conn_send + inc;
            self.flush_all();
            return ();
        }
        let idx = self.find_id(sid);
        if idx == 999999 {
            return self.fail_conn(h2_err_protocol())?;
        }
        if self.reset[idx] == 1 {
            return ();
        }
        if self.send_win[idx] > max - inc {
            return self.fail_conn(h2_err_flow_control())?;
        }
        self.send_win[idx] = self.send_win[idx] + inc;
        self.flush_stream(idx);
        return ();
    }

    fn on_goaway(H2Frame f) -> Result<(), HttpError> {
        if f.stream_id != 0 {
            return self.fail_conn(h2_err_protocol())?;
        }
        let g = match decode_goaway_payload(f.payload) {
            Result::Ok(v) => v,
            Result::Err(_) => {
                self.fail_conn(h2_err_frame_size())?;
                return ();
            },
        };
        self.goaway_recv = 1;
        self.goaway_last = g.last_stream_id;
        return ();
    }

    pub fn on_frame(H2Frame f) -> Result<(), HttpError> {
        if len(f.payload) > self.local_max_frame {
            return self.fail_conn(h2_err_frame_size())?;
        }
        if self.cont_on == 1 {
            if f.typ != frame_type_continuation() {
                return self.fail_conn(h2_err_protocol())?;
            }
            self.on_continuation(f)?;
            return ();
        }
        let typ = f.typ;
        if typ == frame_type_settings() {
            self.on_settings(f)?;
            return ();
        }
        if self.settings_done == 0 {
            return self.fail_conn(h2_err_protocol())?;
        }
        if typ == frame_type_priority() {
            return ();
        }
        if typ == frame_type_ping() {
            return self.on_ping(f)?;
        }
        if typ == frame_type_rst_stream() {
            return self.on_rst(f)?;
        }
        if typ == frame_type_window_update() {
            return self.on_window(f)?;
        }
        if typ == frame_type_headers() {
            self.on_headers(f)?;
            return ();
        }
        if typ == frame_type_data() {
            self.on_data(f)?;
            return ();
        }
        if typ == frame_type_goaway() {
            return self.on_goaway(f)?;
        }
        if typ == frame_type_push_promise() {
            self.on_push_promise(f)?;
            return ();
        }
        if typ == frame_type_continuation() {
            return self.fail_conn(h2_err_protocol())?;
        }
        return ();
    }

    pub fn feed(Vec<byte> chunk) -> Result<(), HttpError> {
        if self.conn_err == 1 {
            http_err_bad_response()?;
        }
        let i = 0;
        while i < len(chunk) {
            self.buf.push(chunk[i]);
            i = i + 1;
        }
        if self.preface_done == 0 {
            self.try_preface()?;
        }
        if self.preface_done == 0 {
            return ();
        }
        let more = 1;
        while more == 1 {
            let n = frame_wire_len(self.buf);
            if n == 0 {
                more = 0;
            } else {
                let slice = bytes_slice(self.buf, 0, n);
                let f = decode_frame(slice)?;
                self.buf = bytes_slice(self.buf, n, len(self.buf));
                self.on_frame(f)?;
            }
        }
        return ();
    }

    pub fn drain() -> Vec<byte> {
        let out = self.outgoing;
        let empty: Vec<byte> = Vec::new();
        self.outgoing = empty;
        return out;
    }

    fn credit(int idx) -> int {
        let m = self.peer_max_frame;
        if self.conn_send < m {
            m = self.conn_send;
        }
        if self.send_win[idx] < m {
            m = self.send_win[idx];
        }
        if m < 0 {
            m = 0;
        }
        return m;
    }

    fn pend_take(int idx, int n) -> Vec<byte> {
        let out: Vec<byte> = Vec::new();
        let base = self.pstart[idx];
        let k = 0;
        while k < n {
            out.push(self.pblob[base + k]);
            k = k + 1;
        }
        let newb: Vec<byte> = Vec::new();
        let starts: Vec<int> = Vec::new();
        let i = 0;
        let ns = len(self.ids);
        while i < ns {
            starts.push(len(newb));
            let off = self.pstart[i];
            let lim = self.plen[i];
            let skip = 0;
            if i == idx {
                skip = n;
            }
            let p = skip;
            while p < lim {
                newb.push(self.pblob[off + p]);
                p = p + 1;
            }
            i = i + 1;
        }
        let j = 0;
        while j < ns {
            self.pstart[j] = starts[j];
            j = j + 1;
        }
        self.plen[idx] = self.plen[idx] - n;
        self.pblob = newb;
        return out;
    }

    fn enqueue_send(int idx, Vec<byte> body, int es) {
        if self.plen[idx] == 0 {
            self.pstart[idx] = len(self.pblob);
        }
        let i = 0;
        while i < len(body) {
            self.pblob.push(body[i]);
            i = i + 1;
        }
        self.plen[idx] = self.plen[idx] + len(body);
        if es != 0 {
            self.pend_es[idx] = 1;
        }
    }

    fn headers_from_flat(int idx, Vec<int> counts, Vec<string> src_n, Vec<string> src_v) -> Headers {
        let skip = 0;
        let i = 0;
        while i < idx {
            skip = skip + counts[i];
            i = i + 1;
        }
        let h = Headers::new();
        let n = counts[idx];
        let j = 0;
        while j < n {
            h.add(src_n[skip + j], src_v[skip + j]);
            j = j + 1;
        }
        return h;
    }

    fn queue_header_block(int sid, Headers h, int end_stream) {
        let block = encode_header_block_with(h, self.encoder);
        let wire = encode_headers_block_frames(sid, block, end_stream, self.peer_max_frame);
        self.queue_bytes(wire);
    }

    fn flush_stream(int idx) {
        let guard = 0;
        while guard < 10000 {
            if self.plen[idx] == 0 {
                if self.tb_on[idx] == 1 {
                    let th = self.headers_from_flat(idx, self.ot_num, self.ot_names, self.ot_values);
                    self.tb_on[idx] = 0;
                    self.queue_header_block(self.ids[idx], th, 1);
                    self.local_es[idx] = 1;
                    self.note_closed(idx);
                } else {
                    if self.pend_es[idx] == 1 {
                        if self.local_es[idx] == 0 {
                            let empty: Vec<byte> = Vec::new();
                            self.queue_frame(data_frame(self.ids[idx], empty, 1));
                            self.local_es[idx] = 1;
                            self.pend_es[idx] = 0;
                            self.note_closed(idx);
                        }
                    }
                }
                return;
            }
            let n = self.credit(idx);
            if n == 0 {
                return;
            }
            if n > self.plen[idx] {
                n = self.plen[idx];
            }
            let chunk = self.pend_take(idx, n);
            self.conn_send = self.conn_send - n;
            self.send_win[idx] = self.send_win[idx] - n;
            let es = 0;
            if self.plen[idx] == 0 {
                if self.tb_on[idx] == 0 {
                    if self.pend_es[idx] == 1 {
                        es = 1;
                        self.pend_es[idx] = 0;
                        self.local_es[idx] = 1;
                    }
                }
            }
            self.queue_frame(data_frame(self.ids[idx], chunk, es));
            if es == 1 {
                self.note_closed(idx);
            }
            guard = guard + 1;
        }
    }

    fn flush_all() {
        let i = 0;
        let n = len(self.ids);
        while i < n {
            self.flush_stream(i);
            i = i + 1;
        }
    }

    fn save_trailer_block(int idx, Headers trailers) {
        let nn: Vec<string> = Vec::new();
        let vv: Vec<string> = Vec::new();
        let i = 0;
        let ns = len(self.ids);
        while i < ns {
            if i == idx {
                let k = 0;
                while k < trailers.count() {
                    nn.push(trailers.name_at(k));
                    vv.push(trailers.value_at(k));
                    k = k + 1;
                }
            } else {
                self.copy_header_range(self.ot_names, self.ot_values, self.ot_num, i, nn, vv);
            }
            i = i + 1;
        }
        self.ot_num[idx] = trailers.count();
        self.ot_names = nn;
        self.ot_values = vv;
        self.tb_on[idx] = 1;
    }

    /// Client: open an odd stream and queue HEADERS plus a request body.
    pub fn write_request(int sid, Headers h, Vec<byte> body) -> Result<(), HttpError> {
        if sid == 0 {
            return self.fail_conn(h2_err_protocol())?;
        }
        if sid % 2 == 0 {
            return self.fail_conn(h2_err_protocol())?;
        }
        if self.goaway_recv == 1 {
            if sid > self.goaway_last {
                http_err_bad_response()?;
            }
        }
        if self.local_streams >= self.peer_max_streams {
            http_err_bad_response()?;
        }
        if self.find_id(sid) != 999999 {
            return self.fail_conn(h2_err_protocol())?;
        }
        self.local_streams = self.local_streams + 1;
        let es = 0;
        if len(body) == 0 {
            es = 1;
        }
        self.push_slot(sid, 0, 0, 0, 0);
        let idx = self.find_id(sid);
        self.queue_header_block(sid, h, es);
        if es == 1 {
            self.local_es[idx] = 1;
            self.note_closed(idx);
        }
        if len(body) > 0 {
            self.enqueue_send(idx, body, 1);
            self.flush_stream(idx);
        }
        return ();
    }

    /// Server: queue the handler response on an existing stream.
    pub fn queue_response(int sid, int status, Headers fields, Vec<byte> body, Headers trailers) -> Result<(), HttpError> {
        let idx = self.find_id(sid);
        if idx == 999999 {
            http_err_bad_response()?;
        }
        let hs = Headers::new();
        hs.add(":status", int_to_dec(status));
        let i = 0;
        while i < fields.count() {
            hs.add(fields.name_at(i), fields.value_at(i));
            i = i + 1;
        }
        let es = 0;
        if len(body) == 0 {
            if trailers.count() == 0 {
                es = 1;
            }
        }
        self.queue_header_block(sid, hs, es);
        if es == 1 {
            self.local_es[idx] = 1;
            self.note_closed(idx);
        }
        if trailers.count() > 0 {
            self.save_trailer_block(idx, trailers);
        }
        if len(body) > 0 {
            let bes = 0;
            if trailers.count() == 0 {
                bes = 1;
            }
            self.enqueue_send(idx, body, bes);
        }
        self.flush_stream(idx);
        self.note_closed(idx);
        return ();
    }

    pub fn stream_count() -> int {
        return len(self.ids);
    }

    /// Drop finished streams so a long sequential session does not scan them.
    pub fn forget_ended() {
        let i = 0;
        let live = 0;
        while i < len(self.ids) {
            if self.plen[i] > 0 {
                return;
            }
            if self.reset[i] == 0 {
                if self.ended[i] == 0 {
                    live = 1;
                }
            }
            i = i + 1;
        }
        if live == 1 {
            return;
        }
        self.ids.clear();
        self.ended.clear();
        self.hnum.clear();
        self.names.clear();
        self.values.clear();
        self.blob.clear();
        self.bstart.clear();
        self.blen.clear();
        self.send_win.clear();
        self.recv_win.clear();
        self.reset.clear();
        self.phase.clear();
        self.pblob.clear();
        self.pstart.clear();
        self.plen.clear();
        self.pend_es.clear();
        self.tnum.clear();
        self.tnames.clear();
        self.tvalues.clear();
        self.tb_on.clear();
        self.ot_num.clear();
        self.ot_names.clear();
        self.ot_values.clear();
        self.local_es.clear();
        self.conc_held.clear();
        self.conc_remote.clear();
        self.local_streams = 0;
        self.remote_streams = 0;
    }

    pub fn stream_headers(int sid) -> Result<Headers, HttpError> {
        let idx = self.find_id(sid);
        if idx == 999999 {
            http_err_bad_response()?;
        }
        return self.headers_from_flat(idx, self.hnum, self.names, self.values);
    }

    pub fn stream_trailers(int sid) -> Result<Headers, HttpError> {
        let idx = self.find_id(sid);
        if idx == 999999 {
            http_err_bad_response()?;
        }
        return self.headers_from_flat(idx, self.tnum, self.tnames, self.tvalues);
    }

    pub fn stream_body(int sid) -> Result<Vec<byte>, HttpError> {
        let idx = self.find_id(sid);
        if idx == 999999 {
            http_err_bad_response()?;
        }
        let off = self.bstart[idx];
        return bytes_slice(self.blob, off, off + self.blen[idx]);
    }

    pub fn stream_ended(int sid) -> Result<int, HttpError> {
        let idx = self.find_id(sid);
        if idx == 999999 {
            http_err_bad_response()?;
        }
        return self.ended[idx];
    }

    pub fn stream_reset(int sid) -> Result<int, HttpError> {
        let idx = self.find_id(sid);
        if idx == 999999 {
            http_err_bad_response()?;
        }
        return self.reset[idx];
    }

    pub fn stream_id_at(int i) -> Result<int, HttpError> {
        if i < 0 {
            http_err_bad_response()?;
        }
        if i >= len(self.ids) {
            http_err_bad_response()?;
        }
        return self.ids[i];
    }

    pub fn goaway_received() -> int {
        return self.goaway_recv;
    }

    pub fn goaway_last_stream() -> int {
        return self.goaway_last;
    }

    pub fn push_count() -> int {
        return len(self.push_ids);
    }

    pub fn push_promised_id(int i) -> Result<int, HttpError> {
        if i < 0 {
            http_err_bad_response()?;
        }
        if i >= len(self.push_ids) {
            http_err_bad_response()?;
        }
        return self.push_ids[i];
    }

    pub fn push_headers(int promised_id) -> Result<Headers, HttpError> {
        let idx = 999999;
        let i = 0;
        let n = len(self.push_ids);
        while i < n {
            if self.push_ids[i] == promised_id {
                idx = i;
            }
            i = i + 1;
        }
        if idx == 999999 {
            http_err_bad_response()?;
        }
        let skip = 0;
        let j = 0;
        while j < idx {
            skip = skip + self.push_hnum[j];
            j = j + 1;
        }
        let h = Headers::new();
        let hn = self.push_hnum[idx];
        let k = 0;
        while k < hn {
            h.add(self.push_names[skip + k], self.push_values[skip + k]);
            k = k + 1;
        }
        return h;
    }
}

/// Two responses from one multiplexed exchange (streams 1 and 3).
class H2Pair {
    pub first: Response,
    pub second: Response,
}

impl H2Pair {
    pub static fn new(Response first, Response second) -> H2Pair {
        return new H2Pair(first, second);
    }
}

fn h2_cat_out(Vec<byte> a, Vec<byte> b) -> Vec<byte> {
    let out: Vec<byte> = Vec::new();
    h2_append_bytes(out, a);
    h2_append_bytes(out, b);
    return out;
}

fn h2s_write(Stream s, Vec<byte> b) -> Result<(), HttpError> {
    if len(b) == 0 {
        return ();
    }
    match write_all(s, b) {
        Result::Ok(_) => 0,
        Result::Err(_) => {
            http_fail_unit()?;
            0
        },
    };
    return ();
}

fn h2_stream_is_ended(H2Session sess, int sid) -> int {
    if sess.find_id(sid) == 999999 {
        return 0;
    }
    let ended = match sess.stream_ended(sid) {
        Result::Ok(v) => v,
        Result::Err(_) => 0,
    };
    return ended;
}

fn h2_pump(Stream s, H2Session sess, int sid1, int sid2, int want2) -> Result<(), HttpError> {
    let guard = 0;
    while guard < 512 {
        let done1 = h2_stream_is_ended(sess, sid1);
        let done2 = 1;
        if want2 == 1 {
            done2 = h2_stream_is_ended(sess, sid2);
        }
        if done1 == 1 {
            if done2 == 1 {
                return ();
            }
        }
        let f = match h2_read_frame(s) {
            Result::Ok(v) => v,
            Result::Err(e) => {
                h2_close(s);
                raise e;
            },
        };
        match sess.feed(encode_frame(f)) {
            Result::Ok(_) => 0,
            Result::Err(e) => {
                match h2s_write(s, sess.drain()) {
                    Result::Ok(_) => 0,
                    Result::Err(_) => 0,
                };
                h2_close(s);
                raise e;
            },
        };
        match h2s_write(s, sess.drain()) {
            Result::Ok(_) => 0,
            Result::Err(e) => {
                h2_close(s);
                raise e;
            },
        };
        guard = guard + 1;
    }
    h2_close(s);
    http_err_bad_response()?;
    return ();
}

fn h2_response_of(H2Session sess, int sid) -> Result<Response, HttpError> {
    let ended = sess.stream_ended(sid)?;
    if ended == 0 {
        http_err_bad_response()?;
    }
    let h = sess.stream_headers(sid)?;
    let body = sess.stream_body(sid)?;
    let tr = sess.stream_trailers(sid)?;
    let r = Response::ok();
    r.status(h2_status_from_headers(h));
    let i = 0;
    while i < h.count() {
        let name = h.name_at(i);
        if name != ":status" {
            r.header(name, h.value_at(i));
        }
        i = i + 1;
    }
    r.body(body);
    let j = 0;
    while j < tr.count() {
        r.trailer(tr.name_at(j), tr.value_at(j));
        j = j + 1;
    }
    return r;
}

fn h2_client_arm(H2Session sess) -> Result<(), HttpError> {
    let st = H2Settings::new();
    st.add(settings_id_enable_push(), 0);
    return sess.queue_local_settings(st)?;
}

/// One request/response on an open HTTP/2 connection. Does not close `s` on success.
/// `preface` 1 writes the client connection preface with the first request bytes.
fn h2_roundtrip(Stream s, H2Session sess, int sid, Url u, string method, Headers extra, Vec<byte> body, int preface) -> Result<Response, HttpError> {
    sess.write_request(sid, h2_request_headers(u, method, extra), body)?;
    let payload = sess.drain();
    let wire = payload;
    if preface == 1 {
        wire = h2_cat_out(connection_preface(), payload);
    }
    match h2s_write(s, wire) {
        Result::Ok(_) => 0,
        Result::Err(e) => {
            h2_close(s);
            raise e;
        },
    };
    h2_pump(s, sess, sid, 0, 0)?;
    let resp = match h2_response_of(sess, sid) {
        Result::Ok(v) => v,
        Result::Err(e) => {
            h2_close(s);
            raise e;
        },
    };
    sess.forget_ended();
    return resp;
}

fn h2_exchange_on(Stream s, Url u, string method, Headers extra, Vec<byte> body) -> Result<Response, HttpError> {
    let sess = H2Session::client();
    h2_client_arm(sess)?;
    let resp = h2_roundtrip(s, sess, 1, u, method, extra, body, 1)?;
    h2_close(s);
    return resp;
}

fn h2_exchange_two_on(Stream s, Url a, Url b) -> Result<H2Pair, HttpError> {
    let sess = H2Session::client();
    h2_client_arm(sess)?;
    let empty = Headers::new();
    let nobody: Vec<byte> = Vec::new();
    sess.write_request(1, h2_request_headers(a, "GET", empty), nobody)?;
    sess.write_request(3, h2_request_headers(b, "GET", empty), nobody)?;
    let wire = h2_cat_out(connection_preface(), sess.drain());
    match h2s_write(s, wire) {
        Result::Ok(_) => 0,
        Result::Err(e) => {
            h2_close(s);
            raise e;
        },
    };
    h2_pump(s, sess, 1, 3, 1)?;
    let first = match h2_response_of(sess, 1) {
        Result::Ok(v) => v,
        Result::Err(e) => {
            h2_close(s);
            raise e;
        },
    };
    let second = match h2_response_of(sess, 3) {
        Result::Ok(v) => v,
        Result::Err(e) => {
            h2_close(s);
            raise e;
        },
    };
    h2_close(s);
    return H2Pair::new(first, second);
}

fn h2_tls_enable(Stream tcp, string host, bool verify, string ca_pem) -> Result<Stream, HttpError> {
    let ca = Option::None;
    if ca_pem != "" {
        ca = Option::Some(ca_pem);
    }
    let s = match tls_enable(tcp, host, new ClientOpts(verify, ca, Option::None, 5000, h2_client_alpn())) {
        Result::Ok(v) => v,
        Result::Err(_) => {
            h2_close(tcp);
            http_fail_stream()?
        },
    };
    return s;
}

fn h2_request_on_url(string url, string method, Headers extra, Vec<byte> body, bool verify, string ca_pem) -> Result<Response, HttpError> {
    let u = parse_url(url)?;
    if u.scheme == "https" {
        let tcp = match tcp_connect(u.host, u.port) {
            Result::Ok(v) => v,
            Result::Err(_) => http_fail_stream()?,
        };
        let s = h2_tls_enable(tcp, u.host, verify, ca_pem)?;
        let proto = match alpn_protocol(s) {
            Result::Ok(p) => p,
            Result::Err(_) => {
                h2_close(s);
                http_err_io()?;
                ""
            },
        };
        if h2_alpn_is_h2(proto) == 1 {
            return h2_exchange_on(s, u, method, extra, body)?;
        }
        return h2_http11_exchange(s, method, u, extra, body)?;
    }
    if u.scheme != "http" {
        http_err_bad_url()?;
    }
    let tcp = match tcp_connect(u.host, u.port) {
        Result::Ok(v) => v,
        Result::Err(_) => http_fail_stream()?,
    };
    return h2_exchange_on(tcp, u, method, extra, body)?;
}

/// HTTP/2 request. Cleartext uses the connection preface. HTTPS uses ALPN and
/// falls back to HTTP/1.1 unless the selected protocol is `h2`.
fn h2_request(string url, string method, Headers extra, Vec<byte> body) -> Result<Response, HttpError> {
    return h2_request_on_url(url, method, extra, body, true, "")?;
}

/// GET: cleartext prior-knowledge, or HTTPS TLS ALPN `h2` with HTTP/1.1 fallback.
fn h2_connect(string url) -> Result<Response, HttpError> {
    let extra = Headers::new();
    let body: Vec<byte> = Vec::new();
    return h2_request(url, "GET", extra, body)?;
}

/// HTTPS GET after TLS enable with optional CA PEM (`""` uses default verify).
fn h2_connect_tls(string url, bool verify, string ca_pem) -> Result<Response, HttpError> {
    let extra = Headers::new();
    let body: Vec<byte> = Vec::new();
    return h2_request_on_url(url, "GET", extra, body, verify, ca_pem)?;
}

/// Two cleartext prior-knowledge GETs on one connection (streams 1 and 3).
fn h2_connect_two(string url_a, string url_b) -> Result<H2Pair, HttpError> {
    let a = parse_url(url_a)?;
    let b = parse_url(url_b)?;
    if a.scheme != "http" {
        http_err_bad_url()?;
    }
    let tcp = match tcp_connect(a.host, a.port) {
        Result::Ok(v) => v,
        Result::Err(_) => http_fail_stream()?,
    };
    return h2_exchange_two_on(tcp, a, b)?;
}

/// HTTP/2 GET on an already-connected stream (prior knowledge or TLS `h2`).
fn h2_get_over_h2(Stream s, Url u) -> Result<Response, HttpError> {
    let extra = Headers::new();
    let body: Vec<byte> = Vec::new();
    return h2_exchange_on(s, u, "GET", extra, body)?;
}

fn h2_origin_key(Url u) -> string {
    return u.scheme + "://" + u.host + ":" + int_to_dec(u.port);
}

/// One HTTP/2 connection held by `Client`. Not the HTTP/1.1 `ConnPool`.
class H2ClientSlot {
    pub on: int,
    pub key: string,
    pub next: int,
    pub stream: Option<Stream>,
    pub sess: Option<H2Session>,
}

fn h2_slot_empty() -> H2ClientSlot {
    return new H2ClientSlot(0, "", 1, Option::None, Option::None);
}

fn h2_slot_close(H2ClientSlot slot) {
    match slot.stream {
        Option::None => 0,
        Option::Some(s) => {
            h2_close(s);
            0
        },
    };
    slot.on = 0;
    slot.key = "";
    slot.next = 1;
    slot.stream = Option::None;
    slot.sess = Option::None;
}

fn h2_slot_mark_dead(H2ClientSlot slot) {
    slot.on = 0;
    slot.key = "";
    slot.next = 1;
    slot.stream = Option::None;
    slot.sess = Option::None;
}

fn h2_slot_can_reuse(H2ClientSlot slot, string key) -> int {
    if slot.on == 0 {
        return 0;
    }
    if slot.key != key {
        return 0;
    }
    if slot.next < 1 {
        return 0;
    }
    if slot.next % 2 == 0 {
        return 0;
    }
    let sess = match slot.sess {
        Option::None => {
            return 0;
        },
        Option::Some(v) => v,
    };
    if sess.goaway_received() == 1 {
        return 0;
    }
    return 1;
}

fn h2_slot_run_first(H2ClientSlot slot, Stream s, Url u, string key, string method, Headers extra, Vec<byte> body) -> Result<Response, HttpError> {
    let sess = H2Session::client();
    match h2_client_arm(sess) {
        Result::Ok(_) => 0,
        Result::Err(e) => {
            h2_close(s);
            raise e;
        },
    };
    let resp = h2_roundtrip(s, sess, 1, u, method, extra, body, 1)?;
    slot.on = 1;
    slot.key = key;
    slot.next = 3;
    slot.stream = Option::Some(s);
    slot.sess = Option::Some(sess);
    return resp;
}

fn h2_slot_dial(H2ClientSlot slot, Url u, string key, string method, Headers extra, Vec<byte> body) -> Result<Response, HttpError> {
    if u.scheme == "https" {
        let tcp = match tcp_connect(u.host, u.port) {
            Result::Ok(v) => v,
            Result::Err(_) => http_fail_stream()?,
        };
        let s = h2_tls_enable(tcp, u.host, true, "")?;
        let proto = match alpn_protocol(s) {
            Result::Ok(p) => p,
            Result::Err(_) => {
                h2_close(s);
                http_err_io()?;
                ""
            },
        };
        if h2_alpn_is_h2(proto) == 0 {
            return h2_http11_exchange(s, method, u, extra, body)?;
        }
        return h2_slot_run_first(slot, s, u, key, method, extra, body)?;
    }
    if u.scheme != "http" {
        http_err_bad_url()?;
    }
    let tcp = match tcp_connect(u.host, u.port) {
        Result::Ok(v) => v,
        Result::Err(_) => http_fail_stream()?,
    };
    return h2_slot_run_first(slot, tcp, u, key, method, extra, body)?;
}

/// Request on this slot. Reuses the live connection for the same origin.
fn h2_slot_exchange(H2ClientSlot slot, string url, string method, Headers extra, Vec<byte> body) -> Result<Response, HttpError> {
    let u = parse_url(url)?;
    let key = h2_origin_key(u);
    if h2_slot_can_reuse(slot, key) == 1 {
        let sid = slot.next;
        let s = match slot.stream {
            Option::None => http_fail_stream()?,
            Option::Some(v) => v,
        };
        let sess = match slot.sess {
            Option::None => {
                http_err_bad_response()?;
                H2Session::client()
            },
            Option::Some(v) => v,
        };
        match h2_roundtrip(s, sess, sid, u, method, extra, body, 0) {
            Result::Ok(r) => {
                slot.next = sid + 2;
                if sess.goaway_received() == 1 {
                    h2_slot_close(slot);
                }
                return r;
            },
            Result::Err(_) => {
                h2_slot_mark_dead(slot);
                0
            },
        };
    } else {
        if slot.on == 1 {
            h2_slot_close(slot);
        }
    }
    return h2_slot_dial(slot, u, key, method, extra, body)?;
}
