// In-memory HTTP/2 session: preface + frames from a buffer, no TLS/sockets.
use http::url::{HttpError, Headers, bytes_slice, http_err_bad_response};
use http::hpack::{HpackTable};
use http::h2::{
    H2Frame,
    connection_preface,
    decode_frame,
    decode_goaway_payload,
    decode_settings_payload,
    decode_window_update_payload,
    encode_frame,
    frame_type_data,
    frame_type_goaway,
    frame_type_headers,
    frame_type_settings,
    frame_type_window_update,
    frame_wire_len,
    headers_from_frame_with,
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
            HpackTable::new(4096)
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
        decode_settings_payload(f.payload)?;
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

    fn on_headers(H2Frame f) -> Result<(), HttpError> {
        self.require_client_sid(f.stream_id)?;
        let h = headers_from_frame_with(f, self.hpack)?;
        let idx = self.find_id(f.stream_id);
        if idx != 999999 {
            http_err_bad_response()?;
        }
        self.ids.push(f.stream_id);
        self.ended.push(f.flags % 2);
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
}
