// In-memory HTTP/2 session: preface + frames from a buffer, no TLS/sockets.
use http::url::{HttpError, Headers, bytes_slice, http_err_bad_response};
use http::hpack::{HpackTable, decode_header_block_with};
use http::h2::{
    H2Frame,
    apply_settings_to_table,
    connection_preface,
    decode_frame,
    decode_goaway_payload,
    decode_push_promise_payload,
    decode_settings_payload,
    decode_window_update_payload,
    encode_frame,
    frame_type_continuation,
    frame_type_data,
    frame_type_goaway,
    frame_type_headers,
    frame_type_push_promise,
    frame_type_settings,
    frame_type_window_update,
    frame_wire_len,
    h2_end_headers_set,
    headers_from_frame_with,
    push_promise_frame,
    settings_ack_frame,
};

/// Server-side session over a byte buffer (client-to-server).
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
}

impl H2Session {
    static fn new() -> H2Session {
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
        return new H2Session(
            0,
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
            push_values
        );
    }

    fn find_id(int sid) -> int {
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

    fn queue_frame(H2Frame f) {
        let wire = encode_frame(f);
        let i = 0;
        while i < len(wire) {
            self.outgoing.push(wire[i]);
            i = i + 1;
        }
    }

    fn try_preface() -> Result<(), HttpError> {
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

    fn on_settings(H2Frame f) -> Result<(), HttpError> {
        if f.stream_id != 0 {
            http_err_bad_response()?;
        }
        let s = decode_settings_payload(f.payload)?;
        apply_settings_to_table(self.hpack, s);
        self.settings_done = 1;
        if f.flags % 2 == 0 {
            self.queue_frame(settings_ack_frame());
        }
        return ();
    }

    fn require_client_sid(int sid) -> Result<(), HttpError> {
        if sid == 0 {
            http_err_bad_response()?;
        }
        if sid % 2 == 0 {
            http_err_bad_response()?;
        }
        return ();
    }

    fn store_headers(int sid, int end_stream, Headers h) -> Result<(), HttpError> {
        let idx = self.find_id(sid);
        if idx != 999999 {
            http_err_bad_response()?;
        }
        self.ids.push(sid);
        self.ended.push(end_stream);
        let n = h.count();
        self.hnum.push(n);
        let i = 0;
        while i < n {
            self.names.push(h.name_at(i));
            self.values.push(h.value_at(i));
            i = i + 1;
        }
        self.bstart.push(len(self.blob));
        self.blen.push(0);
        return ();
    }

    fn finish_headers(int sid, int end_stream, Vec<byte> block) -> Result<(), HttpError> {
        self.require_client_sid(sid)?;
        let h = decode_header_block_with(block, self.hpack)?;
        return self.store_headers(sid, end_stream, h)?;
    }

    fn finish_push(int associated, int promised, Vec<byte> block) -> Result<(), HttpError> {
        self.require_client_sid(associated)?;
        if self.find_id(associated) == 999999 {
            http_err_bad_response()?;
        }
        if promised == 0 {
            http_err_bad_response()?;
        }
        if promised % 2 == 1 {
            http_err_bad_response()?;
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

    fn clear_cont() {
        self.cont_on = 0;
        self.cont_sid = 0;
        self.cont_end_stream = 0;
        self.cont_kind = 0;
        self.cont_promised = 0;
        let empty: Vec<byte> = Vec::new();
        self.cont_buf = empty;
    }

    fn on_headers(H2Frame f) -> Result<(), HttpError> {
        self.require_client_sid(f.stream_id)?;
        if h2_end_headers_set(f.flags) == 1 {
            let h = headers_from_frame_with(f, self.hpack)?;
            return self.store_headers(f.stream_id, f.flags % 2, h)?;
        }
        self.cont_on = 1;
        self.cont_sid = f.stream_id;
        self.cont_end_stream = f.flags % 2;
        self.cont_kind = 1;
        self.cont_promised = 0;
        self.cont_buf = bytes_slice(f.payload, 0, len(f.payload));
        return ();
    }

    fn on_push_promise(H2Frame f) -> Result<(), HttpError> {
        self.require_client_sid(f.stream_id)?;
        if self.find_id(f.stream_id) == 999999 {
            http_err_bad_response()?;
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

    fn on_continuation(H2Frame f) -> Result<(), HttpError> {
        if self.cont_on == 0 {
            http_err_bad_response()?;
        }
        if f.stream_id != self.cont_sid {
            http_err_bad_response()?;
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

    fn queue_push(int associated, int promised, string method, string path, string authority) {
        let h = Headers::new();
        h.add(":method", method);
        h.add(":path", path);
        h.add(":authority", authority);
        self.queue_frame(push_promise_frame(associated, promised, h));
    }

    fn append_body(int idx, Vec<byte> payload) {
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

    fn on_data(H2Frame f) -> Result<(), HttpError> {
        self.require_client_sid(f.stream_id)?;
        let idx = self.find_id(f.stream_id);
        if idx == 999999 {
            http_err_bad_response()?;
        }
        if self.ended[idx] == 1 {
            http_err_bad_response()?;
        }
        self.append_body(idx, f.payload);
        if f.flags % 2 == 1 {
            self.ended[idx] = 1;
        }
        return ();
    }

    fn on_frame(H2Frame f) -> Result<(), HttpError> {
        if self.cont_on == 1 {
            if f.typ != frame_type_continuation() {
                http_err_bad_response()?;
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
            http_err_bad_response()?;
        }
        if typ == frame_type_window_update() {
            decode_window_update_payload(f.payload)?;
            return ();
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
            decode_goaway_payload(f.payload)?;
            return ();
        }
        if typ == frame_type_push_promise() {
            self.on_push_promise(f)?;
            return ();
        }
        if typ == frame_type_continuation() {
            http_err_bad_response()?;
        }
        return ();
    }

    fn feed(Vec<byte> chunk) -> Result<(), HttpError> {
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

    fn drain() -> Vec<byte> {
        let out = self.outgoing;
        let empty: Vec<byte> = Vec::new();
        self.outgoing = empty;
        return out;
    }

    fn stream_count() -> int {
        return len(self.ids);
    }

    fn stream_headers(int sid) -> Result<Headers, HttpError> {
        let idx = self.find_id(sid);
        if idx == 999999 {
            http_err_bad_response()?;
        }
        let skip = 0;
        let i = 0;
        while i < idx {
            skip = skip + self.hnum[i];
            i = i + 1;
        }
        let h = Headers::new();
        let n = self.hnum[idx];
        let j = 0;
        while j < n {
            h.add(self.names[skip + j], self.values[skip + j]);
            j = j + 1;
        }
        return h;
    }

    fn stream_body(int sid) -> Result<Vec<byte>, HttpError> {
        let idx = self.find_id(sid);
        if idx == 999999 {
            http_err_bad_response()?;
        }
        let off = self.bstart[idx];
        return bytes_slice(self.blob, off, off + self.blen[idx]);
    }

    fn stream_ended(int sid) -> Result<int, HttpError> {
        let idx = self.find_id(sid);
        if idx == 999999 {
            http_err_bad_response()?;
        }
        return self.ended[idx];
    }

    fn stream_id_at(int i) -> Result<int, HttpError> {
        if i < 0 {
            http_err_bad_response()?;
        }
        if i >= len(self.ids) {
            http_err_bad_response()?;
        }
        return self.ids[i];
    }

    fn push_count() -> int {
        return len(self.push_ids);
    }

    fn push_promised_id(int i) -> Result<int, HttpError> {
        if i < 0 {
            http_err_bad_response()?;
        }
        if i >= len(self.push_ids) {
            http_err_bad_response()?;
        }
        return self.push_ids[i];
    }

    fn push_headers(int promised_id) -> Result<Headers, HttpError> {
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
