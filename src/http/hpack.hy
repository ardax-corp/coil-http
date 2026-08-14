// HPACK (RFC 7541) static-table header blocks. No Huffman, no dynamic table.
use io::{from_bytes, to_bytes};
use http::url::{
    HttpError,
    Headers,
    bytes_slice,
    http_err_bad_response,
    http_err_not_supported,
};

/// Integer decode cursor (RFC 7541 §5.1).
class HpackInt {
    value: int,
    next: int,
}

impl HpackInt {
    static fn new(int value, int next) -> HpackInt {
        return new HpackInt(value, next);
    }
}

/// String literal decode cursor (RFC 7541 §5.2, H=0 only).
class HpackStr {
    value: string,
    next: int,
}

impl HpackStr {
    static fn new(string value, int next) -> HpackStr {
        return new HpackStr(value, next);
    }
}

fn hpack_push_u8(Vec<byte> out, int n) {
    let mod256 = 128 + 128;
    let b: byte = ((n % mod256) as byte);
    out.push(b);
}

fn hpack_pow2(int nbits) -> int {
    let m = 1;
    let i = 0;
    while i < nbits {
        m = m * 2;
        i = i + 1;
    }
    return m;
}

fn hpack_u8(Vec<byte> raw, int i) -> int {
    return (raw[i] as int);
}

fn hpack_bytes_to_str(Vec<byte> b) -> Result<string, HttpError> {
    return match from_bytes(b) {
        Result::Ok(s) => s,
        Result::Err(_) => {
            http_err_bad_response()?;
            ""
        },
    };
}

/// Encode `value` with an `nbits` prefix. `hi` is the high (8-nbits) bits of the first octet.
fn encode_hpack_int(Vec<byte> out, int value, int nbits, int hi) {
    let two_n = hpack_pow2(nbits);
    let max = two_n - 1;
    let high = hi * two_n;
    if value < max {
        hpack_push_u8(out, high + value);
    } else {
        hpack_push_u8(out, high + max);
        value = value - max;
        while value >= 128 {
            hpack_push_u8(out, (value % 128) + 128);
            value = value / 128;
        }
        hpack_push_u8(out, value);
    }
}

/// Decode an integer with an `nbits` prefix starting at `pos`.
fn decode_hpack_int(Vec<byte> raw, int pos, int nbits) -> Result<HpackInt, HttpError> {
    if pos >= len(raw) {
        http_err_bad_response()?;
    }
    let two_n = hpack_pow2(nbits);
    let max = two_n - 1;
    let b = hpack_u8(raw, pos);
    pos = pos + 1;
    let prefix = b % two_n;
    if prefix < max {
        return HpackInt::new(prefix, pos);
    }
    let n = max;
    let m = 1;
    let cont = 1;
    while cont == 1 {
        if pos >= len(raw) {
            http_err_bad_response()?;
        }
        b = hpack_u8(raw, pos);
        pos = pos + 1;
        n = n + (b % 128) * m;
        if b / 128 == 0 {
            cont = 0;
        } else {
            m = m * 128;
            if m > 1000000000 {
                http_err_bad_response()?;
            }
        }
    }
    return HpackInt::new(n, pos);
}

/// Raw string literal, Huffman bit H=0 (RFC 7541 §5.2).
fn encode_hpack_string(Vec<byte> out, string s) {
    let b = to_bytes(s);
    encode_hpack_int(out, len(b), 7, 0);
    let i = 0;
    while i < len(b) {
        out.push(b[i]);
        i = i + 1;
    }
}

/// Decode a string literal at `pos`. Huffman (H=1) is NotSupported.
fn decode_hpack_string(Vec<byte> raw, int pos) -> Result<HpackStr, HttpError> {
    if pos >= len(raw) {
        http_err_bad_response()?;
    }
    let first = hpack_u8(raw, pos);
    if first / 128 == 1 {
        http_err_not_supported()?;
    }
    let di = decode_hpack_int(raw, pos, 7)?;
    let n = di.value;
    let start = di.next;
    if start + n > len(raw) {
        http_err_bad_response()?;
    }
    let slice = bytes_slice(raw, start, start + n);
    let s = hpack_bytes_to_str(slice)?;
    return HpackStr::new(s, start + n);
}

// Partial RFC 7541 Appendix A: common static entries only; other indices decode as unknown.
fn hpack_static_name(int idx) -> string {
    if idx == 1 {
        return ":authority";
    }
    if idx == 2 {
        return ":method";
    }
    if idx == 3 {
        return ":method";
    }
    if idx == 4 {
        return ":path";
    }
    if idx == 5 {
        return ":path";
    }
    if idx == 6 {
        return ":scheme";
    }
    if idx == 7 {
        return ":scheme";
    }
    if idx == 8 {
        return ":status";
    }
    if idx == 28 {
        return "content-length";
    }
    if idx == 31 {
        return "content-type";
    }
    return "";
}

fn hpack_static_value(int idx) -> string {
    if idx == 2 {
        return "GET";
    }
    if idx == 3 {
        return "POST";
    }
    if idx == 4 {
        return "/";
    }
    if idx == 5 {
        return "/index.html";
    }
    if idx == 6 {
        return "http";
    }
    if idx == 7 {
        return "https";
    }
    if idx == 8 {
        return "200";
    }
    return "";
}

fn hpack_static_match(string name, string value) -> int {
    let i = 1;
    while i < 62 {
        let n = hpack_static_name(i);
        if n == name {
            if hpack_static_value(i) == value {
                return i;
            }
        }
        i = i + 1;
    }
    return 0;
}

fn hpack_static_name_index(string name) -> int {
    let i = 1;
    while i < 62 {
        if hpack_static_name(i) == name {
            return i;
        }
        i = i + 1;
    }
    return 0;
}

/// HEADERS payload: indexed static fields (1xxxxxxx) or literal without indexing (0000xxxx).
fn encode_header_block(Headers h) -> Vec<byte> {
    let out: Vec<byte> = Vec::new();
    let i = 0;
    let n = h.count();
    while i < n {
        let name = h.name_at(i);
        let value = h.value_at(i);
        let both = hpack_static_match(name, value);
        if both == 0 {
            let ni = hpack_static_name_index(name);
            encode_hpack_int(out, ni, 4, 0);
            if ni == 0 {
                encode_hpack_string(out, name);
            }
            encode_hpack_string(out, value);
        } else {
            encode_hpack_int(out, both, 7, 1);
        }
        i = i + 1;
    }
    return out;
}

/// Decode a HEADERS payload into `Headers`. Truncation is BadResponse; Huffman/other representations are NotSupported.
fn decode_header_block(Vec<byte> raw) -> Result<Headers, HttpError> {
    let h = Headers::new();
    let pos = 0;
    while pos < len(raw) {
        let b = hpack_u8(raw, pos);
        if b / 128 == 1 {
            let di = decode_hpack_int(raw, pos, 7)?;
            let idx = di.value;
            let name = hpack_static_name(idx);
            if name == "" {
                http_err_bad_response()?;
            }
            h.add(name, hpack_static_value(idx));
            pos = di.next;
        } else {
            if b / 16 == 0 {
                let di = decode_hpack_int(raw, pos, 4)?;
                let idx = di.value;
                pos = di.next;
                let name = "";
                if idx == 0 {
                    let ns = decode_hpack_string(raw, pos)?;
                    name = ns.value;
                    pos = ns.next;
                } else {
                    name = hpack_static_name(idx);
                    if name == "" {
                        http_err_bad_response()?;
                    }
                }
                let vs = decode_hpack_string(raw, pos)?;
                h.add(name, vs.value);
                pos = vs.next;
            } else {
                http_err_not_supported()?;
            }
        }
    }
    return h;
}
