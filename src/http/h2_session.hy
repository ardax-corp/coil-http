// In-memory HTTP/2 connection: preface, frames, flow control, no sockets.
// Socket loops call this session and write whatever `drain` queues.
use conv::{int_to_dec};
use io::{Stream};
use io::net::tcp::connect as tcp_connect;
use io::sync::{write_all};
use tls::client::{enable as tls_enable, ClientOpts};
use tls::{alpn_protocol};
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
    pub preface_done: int,
    pub settings_done: int,
    pub buf: Vec<byte>,
    pub outgoing: Vec<byte>,
    pub ids: Vec<int>,
    pub ended: Vec<int>,
    pub hnum: Vec<int>,
    pub names: Vec<string>,
    pub values: Vec<string>,
    pub blob: Vec<byte>,
    pub bstart: Vec<int>,
    pub blen: Vec<int>,
    pub hpack: HpackTable,
    pub cont_on: int,
    pub cont_sid: int,
    pub cont_end_stream: int,
    pub cont_kind: int,
    pub cont_promised: int,
    pub cont_buf: Vec<byte>,
    pub push_ids: Vec<int>,
    pub push_hnum: Vec<int>,
    pub push_names: Vec<string>,
    pub push_values: Vec<string>,
    pub role: int,
    pub conn_send: int,
    pub conn_recv: int,
    pub peer_window: int,
    pub local_window: int,
    pub peer_max_frame: int,
    pub local_max_frame: int,
    pub peer_max_streams: int,
    pub local_max_streams: int,
    pub local_enable_push: int,
    pub remote_streams: int,
    pub local_streams: int,
    pub goaway_recv: int,
    pub goaway_last: int,
    pub goaway_sent: int,
    pub last_peer_stream: int,
    pub send_win: Vec<int>,
    pub recv_win: Vec<int>,
    pub reset: Vec<int>,
    pub phase: Vec<int>,
    pub pblob: Vec<byte>,
    pub pstart: Vec<int>,
    pub plen: Vec<int>,
    pub pend_es: Vec<int>,
    pub tnum: Vec<int>,
    pub tnames: Vec<string>,
    pub tvalues: Vec<string>,
    pub encoder: HpackTable,
    pub conn_err: int,
    pub tb_on: Vec<int>,
    pub ot_num: Vec<int>,
    pub ot_names: Vec<string>,
    pub ot_values: Vec<string>,
    pub local_es: Vec<int>,
    pub conc_held: Vec<int>,
    pub conc_remote: Vec<int>,
}
