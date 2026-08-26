// HPACK (RFC 7541): static table, Huffman encode/decode, dynamic table.
// Encode uses Huffman (H=1) when the coded string is shorter; otherwise H=0.
// Literals use incremental indexing (RFC 7541 §6.2.1) so a later block on the
// same HpackTable can emit a dynamic index.
use io::{from_bytes, to_bytes};
use http::url::{
    HttpError,
    Headers,
    bytes_slice,
    http_err_bad_response,
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

/// String literal decode cursor (RFC 7541 §5.2).
class HpackStr {
    value: string,
    next: int,
}

impl HpackStr {
    static fn new(string value, int next) -> HpackStr {
        return new HpackStr(value, next);
    }
}

/// Literal name/value plus resume offset.
class HpackNV {
    name: string,
    value: string,
    next: int,
}

impl HpackNV {
    static fn new(string name, string value, int next) -> HpackNV {
        return new HpackNV(name, value, next);
    }
}

/// Decoder dynamic table (RFC 7541 §2.3). `cap` is SETTINGS_HEADER_TABLE_SIZE.
class HpackTable {
    names: Vec<string>,
    values: Vec<string>,
    cap: int,
    max_size: int,
    size: int,
}

impl HpackTable {
    /// Empty table; `cap` is the SETTINGS limit (RFC default 4096).
    static fn new(int cap) -> HpackTable {
        let names: Vec<string> = Vec::new();
        let values: Vec<string> = Vec::new();
        return new HpackTable(names, values, cap, cap, 0);
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

fn huff_push(Vec<int> codes, Vec<int> lens, int code, int nbits) {
    codes.push(code);
    lens.push(nbits);
}

/// RFC 7541 Appendix B codes, LSB-aligned, plus bit lengths.
fn huff_fill(Vec<int> codes, Vec<int> lens) {
    huff_push(codes, lens, 8184, 13);
    huff_push(codes, lens, 8388568, 23);
    huff_push(codes, lens, 268435426, 28);
    huff_push(codes, lens, 268435427, 28);
    huff_push(codes, lens, 268435428, 28);
    huff_push(codes, lens, 268435429, 28);
    huff_push(codes, lens, 268435430, 28);
    huff_push(codes, lens, 268435431, 28);
    huff_push(codes, lens, 268435432, 28);
    huff_push(codes, lens, 16777194, 24);
    huff_push(codes, lens, 1073741820, 30);
    huff_push(codes, lens, 268435433, 28);
    huff_push(codes, lens, 268435434, 28);
    huff_push(codes, lens, 1073741821, 30);
    huff_push(codes, lens, 268435435, 28);
    huff_push(codes, lens, 268435436, 28);
    huff_push(codes, lens, 268435437, 28);
    huff_push(codes, lens, 268435438, 28);
    huff_push(codes, lens, 268435439, 28);
    huff_push(codes, lens, 268435440, 28);
    huff_push(codes, lens, 268435441, 28);
    huff_push(codes, lens, 268435442, 28);
    huff_push(codes, lens, 1073741822, 30);
    huff_push(codes, lens, 268435443, 28);
    huff_push(codes, lens, 268435444, 28);
    huff_push(codes, lens, 268435445, 28);
    huff_push(codes, lens, 268435446, 28);
    huff_push(codes, lens, 268435447, 28);
    huff_push(codes, lens, 268435448, 28);
    huff_push(codes, lens, 268435449, 28);
    huff_push(codes, lens, 268435450, 28);
    huff_push(codes, lens, 268435451, 28);
    huff_push(codes, lens, 20, 6);
    huff_push(codes, lens, 1016, 10);
    huff_push(codes, lens, 1017, 10);
    huff_push(codes, lens, 4090, 12);
    huff_push(codes, lens, 8185, 13);
    huff_push(codes, lens, 21, 6);
    huff_push(codes, lens, 248, 8);
    huff_push(codes, lens, 2042, 11);
    huff_push(codes, lens, 1018, 10);
    huff_push(codes, lens, 1019, 10);
    huff_push(codes, lens, 249, 8);
    huff_push(codes, lens, 2043, 11);
    huff_push(codes, lens, 250, 8);
    huff_push(codes, lens, 22, 6);
    huff_push(codes, lens, 23, 6);
    huff_push(codes, lens, 24, 6);
    huff_push(codes, lens, 0, 5);
    huff_push(codes, lens, 1, 5);
    huff_push(codes, lens, 2, 5);
    huff_push(codes, lens, 25, 6);
    huff_push(codes, lens, 26, 6);
    huff_push(codes, lens, 27, 6);
    huff_push(codes, lens, 28, 6);
    huff_push(codes, lens, 29, 6);
    huff_push(codes, lens, 30, 6);
    huff_push(codes, lens, 31, 6);
    huff_push(codes, lens, 92, 7);
    huff_push(codes, lens, 251, 8);
    huff_push(codes, lens, 32764, 15);
    huff_push(codes, lens, 32, 6);
    huff_push(codes, lens, 4091, 12);
    huff_push(codes, lens, 1020, 10);
    huff_push(codes, lens, 8186, 13);
    huff_push(codes, lens, 33, 6);
    huff_push(codes, lens, 93, 7);
    huff_push(codes, lens, 94, 7);
    huff_push(codes, lens, 95, 7);
    huff_push(codes, lens, 96, 7);
    huff_push(codes, lens, 97, 7);
    huff_push(codes, lens, 98, 7);
    huff_push(codes, lens, 99, 7);
    huff_push(codes, lens, 100, 7);
    huff_push(codes, lens, 101, 7);
    huff_push(codes, lens, 102, 7);
    huff_push(codes, lens, 103, 7);
    huff_push(codes, lens, 104, 7);
    huff_push(codes, lens, 105, 7);
    huff_push(codes, lens, 106, 7);
    huff_push(codes, lens, 107, 7);
    huff_push(codes, lens, 108, 7);
    huff_push(codes, lens, 109, 7);
    huff_push(codes, lens, 110, 7);
    huff_push(codes, lens, 111, 7);
    huff_push(codes, lens, 112, 7);
    huff_push(codes, lens, 113, 7);
    huff_push(codes, lens, 114, 7);
    huff_push(codes, lens, 252, 8);
    huff_push(codes, lens, 115, 7);
    huff_push(codes, lens, 253, 8);
    huff_push(codes, lens, 8187, 13);
    huff_push(codes, lens, 524272, 19);
    huff_push(codes, lens, 8188, 13);
    huff_push(codes, lens, 16380, 14);
    huff_push(codes, lens, 34, 6);
    huff_push(codes, lens, 32765, 15);
    huff_push(codes, lens, 3, 5);
    huff_push(codes, lens, 35, 6);
    huff_push(codes, lens, 4, 5);
    huff_push(codes, lens, 36, 6);
    huff_push(codes, lens, 5, 5);
    huff_push(codes, lens, 37, 6);
    huff_push(codes, lens, 38, 6);
    huff_push(codes, lens, 39, 6);
    huff_push(codes, lens, 6, 5);
    huff_push(codes, lens, 116, 7);
    huff_push(codes, lens, 117, 7);
    huff_push(codes, lens, 40, 6);
    huff_push(codes, lens, 41, 6);
    huff_push(codes, lens, 42, 6);
    huff_push(codes, lens, 7, 5);
    huff_push(codes, lens, 43, 6);
    huff_push(codes, lens, 118, 7);
    huff_push(codes, lens, 44, 6);
    huff_push(codes, lens, 8, 5);
    huff_push(codes, lens, 9, 5);
    huff_push(codes, lens, 45, 6);
    huff_push(codes, lens, 119, 7);
    huff_push(codes, lens, 120, 7);
    huff_push(codes, lens, 121, 7);
    huff_push(codes, lens, 122, 7);
    huff_push(codes, lens, 123, 7);
    huff_push(codes, lens, 32766, 15);
    huff_push(codes, lens, 2044, 11);
    huff_push(codes, lens, 16381, 14);
    huff_push(codes, lens, 8189, 13);
    huff_push(codes, lens, 268435452, 28);
    huff_push(codes, lens, 1048550, 20);
    huff_push(codes, lens, 4194258, 22);
    huff_push(codes, lens, 1048551, 20);
    huff_push(codes, lens, 1048552, 20);
    huff_push(codes, lens, 4194259, 22);
    huff_push(codes, lens, 4194260, 22);
    huff_push(codes, lens, 4194261, 22);
    huff_push(codes, lens, 8388569, 23);
    huff_push(codes, lens, 4194262, 22);
    huff_push(codes, lens, 8388570, 23);
    huff_push(codes, lens, 8388571, 23);
    huff_push(codes, lens, 8388572, 23);
    huff_push(codes, lens, 8388573, 23);
    huff_push(codes, lens, 8388574, 23);
    huff_push(codes, lens, 16777195, 24);
    huff_push(codes, lens, 8388575, 23);
    huff_push(codes, lens, 16777196, 24);
    huff_push(codes, lens, 16777197, 24);
    huff_push(codes, lens, 4194263, 22);
    huff_push(codes, lens, 8388576, 23);
    huff_push(codes, lens, 16777198, 24);
    huff_push(codes, lens, 8388577, 23);
    huff_push(codes, lens, 8388578, 23);
    huff_push(codes, lens, 8388579, 23);
    huff_push(codes, lens, 8388580, 23);
    huff_push(codes, lens, 2097116, 21);
    huff_push(codes, lens, 4194264, 22);
    huff_push(codes, lens, 8388581, 23);
    huff_push(codes, lens, 4194265, 22);
    huff_push(codes, lens, 8388582, 23);
    huff_push(codes, lens, 8388583, 23);
    huff_push(codes, lens, 16777199, 24);
    huff_push(codes, lens, 4194266, 22);
    huff_push(codes, lens, 2097117, 21);
    huff_push(codes, lens, 1048553, 20);
    huff_push(codes, lens, 4194267, 22);
    huff_push(codes, lens, 4194268, 22);
    huff_push(codes, lens, 8388584, 23);
    huff_push(codes, lens, 8388585, 23);
    huff_push(codes, lens, 2097118, 21);
    huff_push(codes, lens, 8388586, 23);
    huff_push(codes, lens, 4194269, 22);
    huff_push(codes, lens, 4194270, 22);
    huff_push(codes, lens, 16777200, 24);
    huff_push(codes, lens, 2097119, 21);
    huff_push(codes, lens, 4194271, 22);
    huff_push(codes, lens, 8388587, 23);
    huff_push(codes, lens, 8388588, 23);
    huff_push(codes, lens, 2097120, 21);
    huff_push(codes, lens, 2097121, 21);
    huff_push(codes, lens, 4194272, 22);
    huff_push(codes, lens, 2097122, 21);
    huff_push(codes, lens, 8388589, 23);
    huff_push(codes, lens, 4194273, 22);
    huff_push(codes, lens, 8388590, 23);
    huff_push(codes, lens, 8388591, 23);
    huff_push(codes, lens, 1048554, 20);
    huff_push(codes, lens, 4194274, 22);
    huff_push(codes, lens, 4194275, 22);
    huff_push(codes, lens, 4194276, 22);
    huff_push(codes, lens, 8388592, 23);
    huff_push(codes, lens, 4194277, 22);
    huff_push(codes, lens, 4194278, 22);
    huff_push(codes, lens, 8388593, 23);
    huff_push(codes, lens, 67108832, 26);
    huff_push(codes, lens, 67108833, 26);
    huff_push(codes, lens, 1048555, 20);
    huff_push(codes, lens, 524273, 19);
    huff_push(codes, lens, 4194279, 22);
    huff_push(codes, lens, 8388594, 23);
    huff_push(codes, lens, 4194280, 22);
    huff_push(codes, lens, 33554412, 25);
    huff_push(codes, lens, 67108834, 26);
    huff_push(codes, lens, 67108835, 26);
    huff_push(codes, lens, 67108836, 26);
    huff_push(codes, lens, 134217694, 27);
    huff_push(codes, lens, 134217695, 27);
    huff_push(codes, lens, 67108837, 26);
    huff_push(codes, lens, 16777201, 24);
    huff_push(codes, lens, 33554413, 25);
    huff_push(codes, lens, 524274, 19);
    huff_push(codes, lens, 2097123, 21);
    huff_push(codes, lens, 67108838, 26);
    huff_push(codes, lens, 134217696, 27);
    huff_push(codes, lens, 134217697, 27);
    huff_push(codes, lens, 67108839, 26);
    huff_push(codes, lens, 134217698, 27);
    huff_push(codes, lens, 16777202, 24);
    huff_push(codes, lens, 2097124, 21);
    huff_push(codes, lens, 2097125, 21);
    huff_push(codes, lens, 67108840, 26);
    huff_push(codes, lens, 67108841, 26);
    huff_push(codes, lens, 268435453, 28);
    huff_push(codes, lens, 134217699, 27);
    huff_push(codes, lens, 134217700, 27);
    huff_push(codes, lens, 134217701, 27);
    huff_push(codes, lens, 1048556, 20);
    huff_push(codes, lens, 16777203, 24);
    huff_push(codes, lens, 1048557, 20);
    huff_push(codes, lens, 2097126, 21);
    huff_push(codes, lens, 4194281, 22);
    huff_push(codes, lens, 2097127, 21);
    huff_push(codes, lens, 2097128, 21);
    huff_push(codes, lens, 8388595, 23);
    huff_push(codes, lens, 4194282, 22);
    huff_push(codes, lens, 4194283, 22);
    huff_push(codes, lens, 33554414, 25);
    huff_push(codes, lens, 33554415, 25);
    huff_push(codes, lens, 16777204, 24);
    huff_push(codes, lens, 16777205, 24);
    huff_push(codes, lens, 67108842, 26);
    huff_push(codes, lens, 8388596, 23);
    huff_push(codes, lens, 67108843, 26);
    huff_push(codes, lens, 134217702, 27);
    huff_push(codes, lens, 67108844, 26);
    huff_push(codes, lens, 67108845, 26);
    huff_push(codes, lens, 134217703, 27);
    huff_push(codes, lens, 134217704, 27);
    huff_push(codes, lens, 134217705, 27);
    huff_push(codes, lens, 134217706, 27);
    huff_push(codes, lens, 134217707, 27);
    huff_push(codes, lens, 268435454, 28);
    huff_push(codes, lens, 134217708, 27);
    huff_push(codes, lens, 134217709, 27);
    huff_push(codes, lens, 134217710, 27);
    huff_push(codes, lens, 134217711, 27);
    huff_push(codes, lens, 134217712, 27);
    huff_push(codes, lens, 67108846, 26);

}

fn decode_hpack_huffman(Vec<byte> raw) -> Result<string, HttpError> {
    let codes: Vec<int> = Vec::new();
    let lens: Vec<int> = Vec::new();
    huff_fill(codes, lens);
    let outb: Vec<byte> = Vec::new();
    let cur = 0;
    let nbits = 0;
    let i = 0;
    while i < len(raw) {
        let b = hpack_u8(raw, i);
        let sh = 7;
        while sh >= 0 {
            let bit = (b >> sh) & 1;
            cur = (cur << 1) | bit;
            nbits = nbits + 1;
            let found = 256;
            let s = 0;
            while s < 256 {
                if lens[s] == nbits {
                    if codes[s] == cur {
                        found = s;
                    }
                }
                s = s + 1;
            }
            if found < 256 {
                hpack_push_u8(outb, found);
                cur = 0;
                nbits = 0;
            } else {
                if nbits > 30 {
                    http_err_bad_response()?;
                }
            }
            sh = sh - 1;
        }
        i = i + 1;
    }
    if nbits > 7 {
        http_err_bad_response()?;
    }
    if nbits > 0 {
        let ones = hpack_pow2(nbits) - 1;
        if cur != ones {
            http_err_bad_response()?;
        }
    }
    return hpack_bytes_to_str(outb)?;
}

/// RFC 7541 Appendix B Huffman coding, padded with 1-bits to an octet boundary.
fn encode_hpack_huffman(Vec<byte> raw) -> Vec<byte> {
    let codes: Vec<int> = Vec::new();
    let lens: Vec<int> = Vec::new();
    huff_fill(codes, lens);
    let out: Vec<byte> = Vec::new();
    let acc = 0;
    let nbits = 0;
    let i = 0;
    while i < len(raw) {
        let ch = hpack_u8(raw, i);
        let code = codes[ch];
        let blen = lens[ch];
        let bitpos = blen - 1;
        while bitpos >= 0 {
            let bit = (code >> bitpos) & 1;
            acc = (acc << 1) | bit;
            nbits = nbits + 1;
            if nbits == 8 {
                hpack_push_u8(out, acc);
                acc = 0;
                nbits = 0;
            }
            bitpos = bitpos - 1;
        }
        i = i + 1;
    }
    if nbits > 0 {
        let pad = 8 - nbits;
        let ones = hpack_pow2(pad) - 1;
        acc = (acc << pad) | ones;
        hpack_push_u8(out, acc);
    }
    return out;
}

/// String literal: Huffman (H=1) when strictly shorter, otherwise raw (H=0).
fn encode_hpack_string(Vec<byte> out, string s) {
    let b = to_bytes(s);
    let huff = encode_hpack_huffman(b);
    if len(huff) < len(b) {
        encode_hpack_int(out, len(huff), 7, 1);
        let i = 0;
        while i < len(huff) {
            out.push(huff[i]);
            i = i + 1;
        }
    } else {
        encode_hpack_int(out, len(b), 7, 0);
        let i = 0;
        while i < len(b) {
            out.push(b[i]);
            i = i + 1;
        }
    }
}

/// Decode a string literal at `pos`. Huffman (H=1) uses RFC 7541 Appendix B.
fn decode_hpack_string(Vec<byte> raw, int pos) -> Result<HpackStr, HttpError> {
    if pos >= len(raw) {
        http_err_bad_response()?;
    }
    let first = hpack_u8(raw, pos);
    let huff = first / 128;
    let di = decode_hpack_int(raw, pos, 7)?;
    let n = di.value;
    let start = di.next;
    if start + n > len(raw) {
        http_err_bad_response()?;
    }
    let slice = bytes_slice(raw, start, start + n);
    let s = "";
    if huff == 1 {
        s = decode_hpack_huffman(slice)?;
    } else {
        s = hpack_bytes_to_str(slice)?;
    }
    return HpackStr::new(s, start + n);
}

// RFC 7541 Appendix A static table (61 entries).
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
    if idx == 9 {
        return ":status";
    }
    if idx == 10 {
        return ":status";
    }
    if idx == 11 {
        return ":status";
    }
    if idx == 12 {
        return ":status";
    }
    if idx == 13 {
        return ":status";
    }
    if idx == 14 {
        return ":status";
    }
    if idx == 15 {
        return "accept-charset";
    }
    if idx == 16 {
        return "accept-encoding";
    }
    if idx == 17 {
        return "accept-language";
    }
    if idx == 18 {
        return "accept-ranges";
    }
    if idx == 19 {
        return "accept";
    }
    if idx == 20 {
        return "access-control-allow-origin";
    }
    if idx == 21 {
        return "age";
    }
    if idx == 22 {
        return "allow";
    }
    if idx == 23 {
        return "authorization";
    }
    if idx == 24 {
        return "cache-control";
    }
    if idx == 25 {
        return "content-disposition";
    }
    if idx == 26 {
        return "content-encoding";
    }
    if idx == 27 {
        return "content-language";
    }
    if idx == 28 {
        return "content-length";
    }
    if idx == 29 {
        return "content-location";
    }
    if idx == 30 {
        return "content-range";
    }
    if idx == 31 {
        return "content-type";
    }
    if idx == 32 {
        return "cookie";
    }
    if idx == 33 {
        return "date";
    }
    if idx == 34 {
        return "etag";
    }
    if idx == 35 {
        return "expect";
    }
    if idx == 36 {
        return "expires";
    }
    if idx == 37 {
        return "from";
    }
    if idx == 38 {
        return "host";
    }
    if idx == 39 {
        return "if-match";
    }
    if idx == 40 {
        return "if-modified-since";
    }
    if idx == 41 {
        return "if-none-match";
    }
    if idx == 42 {
        return "if-range";
    }
    if idx == 43 {
        return "if-unmodified-since";
    }
    if idx == 44 {
        return "last-modified";
    }
    if idx == 45 {
        return "link";
    }
    if idx == 46 {
        return "location";
    }
    if idx == 47 {
        return "max-forwards";
    }
    if idx == 48 {
        return "proxy-authenticate";
    }
    if idx == 49 {
        return "proxy-authorization";
    }
    if idx == 50 {
        return "range";
    }
    if idx == 51 {
        return "referer";
    }
    if idx == 52 {
        return "refresh";
    }
    if idx == 53 {
        return "retry-after";
    }
    if idx == 54 {
        return "server";
    }
    if idx == 55 {
        return "set-cookie";
    }
    if idx == 56 {
        return "strict-transport-security";
    }
    if idx == 57 {
        return "transfer-encoding";
    }
    if idx == 58 {
        return "user-agent";
    }
    if idx == 59 {
        return "vary";
    }
    if idx == 60 {
        return "via";
    }
    if idx == 61 {
        return "www-authenticate";
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
    if idx == 9 {
        return "204";
    }
    if idx == 10 {
        return "206";
    }
    if idx == 11 {
        return "304";
    }
    if idx == 12 {
        return "400";
    }
    if idx == 13 {
        return "404";
    }
    if idx == 14 {
        return "500";
    }
    if idx == 16 {
        return "gzip, deflate";
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

fn hpack_entry_octets(string name, string value) -> int {
    return len(to_bytes(name)) + len(to_bytes(value)) + 32;
}

fn hpack_table_evict_oldest(HpackTable t) {
    if len(t.names) > 0 {
        let drop = hpack_entry_octets(t.names[0], t.values[0]);
        let nn: Vec<string> = Vec::new();
        let vv: Vec<string> = Vec::new();
        let i = 1;
        while i < len(t.names) {
            nn.push(t.names[i]);
            vv.push(t.values[i]);
            i = i + 1;
        }
        t.names = nn;
        t.values = vv;
        t.size = t.size - drop;
    }
}

fn hpack_table_clear(HpackTable t) {
    let nn: Vec<string> = Vec::new();
    let vv: Vec<string> = Vec::new();
    t.names = nn;
    t.values = vv;
    t.size = 0;
}

fn hpack_table_add(HpackTable t, string name, string value) {
    let es = hpack_entry_octets(name, value);
    if es > t.max_size {
        hpack_table_clear(t);
    } else {
        while t.size + es > t.max_size {
            hpack_table_evict_oldest(t);
        }
        t.names.push(name);
        t.values.push(value);
        t.size = t.size + es;
    }
}

fn hpack_table_set_max(HpackTable t, int max) -> Result<(), HttpError> {
    if max > t.cap {
        http_err_bad_response()?;
    }
    t.max_size = max;
    while t.size > t.max_size {
        hpack_table_evict_oldest(t);
    }
    return ();
}

/// Apply SETTINGS_HEADER_TABLE_SIZE: both decoder cap and max become `cap`.
fn hpack_table_resize(HpackTable t, int cap) {
    if cap < 0 {
        cap = 0;
    }
    t.cap = cap;
    t.max_size = cap;
    while t.size > t.max_size {
        hpack_table_evict_oldest(t);
    }
}

fn hpack_dynamic_match(HpackTable t, string name, string value) -> int {
    let count = len(t.names);
    let found = 0;
    let i = 0;
    while i < count {
        if t.names[i] == name {
            if t.values[i] == value {
                found = 62 + (count - 1 - i);
            }
        }
        i = i + 1;
    }
    return found;
}

fn hpack_name_index(HpackTable t, string name) -> int {
    let si = hpack_static_name_index(name);
    if si != 0 {
        return si;
    }
    let count = len(t.names);
    let found = 0;
    let i = 0;
    while i < count {
        if t.names[i] == name {
            found = 62 + (count - 1 - i);
        }
        i = i + 1;
    }
    return found;
}

fn hpack_lookup_name(HpackTable t, int idx) -> Result<string, HttpError> {
    if idx <= 0 {
        http_err_bad_response()?;
    }
    if idx < 62 {
        let sname = hpack_static_name(idx);
        if sname == "" {
            http_err_bad_response()?;
        }
        return sname;
    }
    let count = len(t.names);
    let di = idx - 62;
    if di >= count {
        http_err_bad_response()?;
    }
    return t.names[count - 1 - di];
}

fn hpack_lookup_value(HpackTable t, int idx) -> Result<string, HttpError> {
    if idx <= 0 {
        http_err_bad_response()?;
    }
    if idx < 62 {
        let sname = hpack_static_name(idx);
        if sname == "" {
            http_err_bad_response()?;
        }
        return hpack_static_value(idx);
    }
    let count = len(t.names);
    let di = idx - 62;
    if di >= count {
        http_err_bad_response()?;
    }
    return t.values[count - 1 - di];
}

fn decode_hpack_nv(Vec<byte> raw, int pos, int nbits, HpackTable t) -> Result<HpackNV, HttpError> {
    let di = decode_hpack_int(raw, pos, nbits)?;
    let idx = di.value;
    pos = di.next;
    let name = "";
    if idx == 0 {
        let ns = decode_hpack_string(raw, pos)?;
        name = ns.value;
        pos = ns.next;
    } else {
        name = hpack_lookup_name(t, idx)?;
    }
    let vs = decode_hpack_string(raw, pos)?;
    return HpackNV::new(name, vs.value, vs.next);
}

/// HEADERS payload: indexed (1xxxxxxx) or literal with incremental indexing (01xxxxxx).
fn encode_header_block_with(Headers h, HpackTable t) -> Vec<byte> {
    let out: Vec<byte> = Vec::new();
    let i = 0;
    let n = h.count();
    while i < n {
        let name = h.name_at(i);
        let value = h.value_at(i);
        let both = hpack_static_match(name, value);
        if both == 0 {
            both = hpack_dynamic_match(t, name, value);
        }
        if both == 0 {
            let ni = hpack_name_index(t, name);
            encode_hpack_int(out, ni, 6, 1);
            if ni == 0 {
                encode_hpack_string(out, name);
            }
            encode_hpack_string(out, value);
            hpack_table_add(t, name, value);
        } else {
            encode_hpack_int(out, both, 7, 1);
        }
        i = i + 1;
    }
    return out;
}

/// One-shot encode into a fresh 4096-octet table.
fn encode_header_block(Headers h) -> Vec<byte> {
    return encode_header_block_with(h, HpackTable::new(4096));
}

/// Decode a HEADERS payload, mutating `t` (incremental indexing / size updates).
fn decode_header_block_with(Vec<byte> raw, HpackTable t) -> Result<Headers, HttpError> {
    let h = Headers::new();
    let pos = 0;
    let seen = 0;
    while pos < len(raw) {
        let b = hpack_u8(raw, pos);
        if b / 128 == 1 {
            seen = 1;
            let di = decode_hpack_int(raw, pos, 7)?;
            let idx = di.value;
            let name = hpack_lookup_name(t, idx)?;
            let value = hpack_lookup_value(t, idx)?;
            h.add(name, value);
            pos = di.next;
        } else {
            if b / 64 == 1 {
                seen = 1;
                let nv = decode_hpack_nv(raw, pos, 6, t)?;
                hpack_table_add(t, nv.name, nv.value);
                h.add(nv.name, nv.value);
                pos = nv.next;
            } else {
                if b / 32 == 1 {
                    if seen == 1 {
                        http_err_bad_response()?;
                    }
                    let di = decode_hpack_int(raw, pos, 5)?;
                    hpack_table_set_max(t, di.value)?;
                    pos = di.next;
                } else {
                    seen = 1;
                    let nv = decode_hpack_nv(raw, pos, 4, t)?;
                    h.add(nv.name, nv.value);
                    pos = nv.next;
                }
            }
        }
    }
    return h;
}

/// Decode a HEADERS payload into `Headers`. Uses a fresh 4096-octet dynamic table.
fn decode_header_block(Vec<byte> raw) -> Result<Headers, HttpError> {
    return decode_header_block_with(raw, HpackTable::new(4096))?;
}
