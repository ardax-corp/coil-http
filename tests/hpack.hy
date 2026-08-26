// HPACK header block tests (Huffman decode, dynamic table, Appendix A).
use http::url::{Headers};
use io::{to_bytes};
use http::hpack::{
    HpackTable,
    decode_header_block,
    decode_header_block_with,
    decode_hpack_int,
    decode_hpack_string,
    encode_header_block,
    encode_header_block_with,
    encode_hpack_huffman,
    encode_hpack_int,
    encode_hpack_string,
    hpack_table_resize,
};

fn hpack_octets(int... xs) -> Vec<byte> {
    let out: Vec<byte> = Vec::new();
    let i = 0;
    while i < len(xs) {
        out.push(xs[i] as byte);
        i = i + 1;
    }
    return out;
}

test("hpack int small roundtrip") {
    let out: Vec<byte> = Vec::new();
    encode_hpack_int(out, 10, 5, 0);
    let d = match decode_hpack_int(out, 0, 5) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode int",
    };
    assert(d.value == 10, "value")?;
    assert(d.next == len(out), "consumed")?;
    assert(len(out) == 1, "fits prefix")?;
}

test("hpack int above prefix roundtrip") {
    let out: Vec<byte> = Vec::new();
    encode_hpack_int(out, 1337, 5, 0);
    assert(len(out) == 3, "3 bytes")?;
    assert((out[0] as int) == 31, "prefix ones")?;
    assert((out[1] as int) == 154, "cont")?;
    assert((out[2] as int) == 10, "last")?;
    let d = match decode_hpack_int(out, 0, 5) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode 1337",
    };
    assert(d.value == 1337, "1337")?;
    assert(d.next == 3, "consumed 3")?;
}

test("hpack string literal roundtrip") {
    let out: Vec<byte> = Vec::new();
    encode_hpack_string(out, "hello");
    let d = match decode_hpack_string(out, 0) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode str",
    };
    assert(d.value == "hello", "hello")?;
    assert(d.next == len(out), "consumed")?;
}

test("encode GET path slash uses static indices") {
    let h = Headers::new();
    h.add(":method", "GET");
    h.add(":path", "/");
    let block = encode_header_block(h);
    assert(len(block) == 2, "two indexed")?;
    assert((block[0] as int) == 130, "index 2")?;
    assert((block[1] as int) == 132, "index 4")?;
    let g = match decode_header_block(block) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode block",
    };
    assert(g.count() == 2, "two headers")?;
    assert(g.name_at(0) == ":method", "method name")?;
    assert(g.value_at(0) == "GET", "GET")?;
    assert(g.name_at(1) == ":path", "path name")?;
    assert(g.value_at(1) == "/", "slash")?;
}

test("literal with incremental indexing new name") {
    let h = Headers::new();
    h.add("x-trace", "abc");
    let block = encode_header_block(h);
    assert((block[0] as int) == 64, "index 0 incremental")?;
    let g = match decode_header_block(block) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode literal",
    };
    assert(g.count() == 1, "one")?;
    assert(g.name_at(0) == "x-trace", "name")?;
    assert(g.value_at(0) == "abc", "value")?;
}

test("content-type uses name index 31") {
    let h = Headers::new();
    h.add("content-type", "text/plain");
    h.add(":status", "200");
    let block = encode_header_block(h);
    let g = match decode_header_block(block) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode ct",
    };
    assert(g.count() == 2, "two")?;
    assert(g.name_at(0) == "content-type", "ct")?;
    assert(g.value_at(0) == "text/plain", "plain")?;
    assert(g.name_at(1) == ":status", "status")?;
    assert(g.value_at(1) == "200", "200")?;
}

test("truncated header block is an error") {
    let raw: Vec<byte> = Vec::new();
    raw.push(255 as byte);
    let r = decode_header_block(raw);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "truncated int")?;
}

test("truncated string literal is an error") {
    let raw: Vec<byte> = Vec::new();
    raw.push(0 as byte);
    raw.push(5 as byte);
    raw.push(("a" as byte));
    let r = decode_header_block(raw);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "truncated str")?;
}

test("huffman string decodes www.example.com") {
    // RFC 7541 C.4.1 literal value (H=1, 12 octets).
    let raw = hpack_octets(140, 241, 227, 194, 229, 242, 58, 107, 160, 171, 144, 244, 255);
    let d = match decode_hpack_string(raw, 0) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "huffman www.example.com",
    };
    assert(d.value == "www.example.com", "www.example.com")?;
    assert(d.next == len(raw), "consumed")?;
}

test("huffman encode www.example.com matches C.4.1") {
    let raw = encode_hpack_huffman(to_bytes("www.example.com"));
    let want = hpack_octets(241, 227, 194, 229, 242, 58, 107, 160, 171, 144, 244, 255);
    assert(len(raw) == 12, "12 octets")?;
    let i = 0;
    while i < 12 {
        assert((raw[i] as int) == (want[i] as int), "c41 byte")?;
        i = i + 1;
    }
}

test("hpack string uses H=1 when huffman is shorter") {
    let out: Vec<byte> = Vec::new();
    encode_hpack_string(out, "www.example.com");
    assert((out[0] as int) / 128 == 1, "H=1")?;
    assert((out[0] as int) % 128 == 12, "len 12")?;
    let d = match decode_hpack_string(out, 0) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "roundtrip huffman",
    };
    assert(d.value == "www.example.com", "value")?;
    assert(d.next == len(out), "consumed")?;
}

test("hpack string encode decode roundtrip hello") {
    let out: Vec<byte> = Vec::new();
    encode_hpack_string(out, "hello");
    let d = match decode_hpack_string(out, 0) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "hello",
    };
    assert(d.value == "hello", "hello")?;
    assert(d.next == len(out), "consumed")?;
}

test("hpack string encode decode roundtrip empty") {
    let out: Vec<byte> = Vec::new();
    encode_hpack_string(out, "");
    assert((out[0] as int) / 128 == 0, "H=0 equal length")?;
    let d = match decode_hpack_string(out, 0) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "empty",
    };
    assert(d.value == "", "empty")?;
    assert(d.next == len(out), "consumed")?;
}

test("hpack string encode decode roundtrip slash") {
    let out: Vec<byte> = Vec::new();
    encode_hpack_string(out, "/");
    let d = match decode_hpack_string(out, 0) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "slash",
    };
    assert(d.value == "/", "slash")?;
}

test("header block encode decode roundtrip with huffman values") {
    let h = Headers::new();
    h.add("x-trace", "www.example.com");
    h.add("content-type", "text/plain");
    let block = encode_header_block(h);
    let g = match decode_header_block(block) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "block roundtrip",
    };
    assert(g.count() == 2, "two")?;
    assert(g.name_at(0) == "x-trace", "name0")?;
    assert(g.value_at(0) == "www.example.com", "val0")?;
    assert(g.name_at(1) == "content-type", "name1")?;
    assert(g.value_at(1) == "text/plain", "val1")?;
}

test("hpack table resize from SETTINGS shrinks cap and max") {
    let t = HpackTable::new(4096);
    assert(t.cap == 4096, "default cap")?;
    assert(t.max_size == 4096, "default max")?;
    hpack_table_resize(t, 256);
    assert(t.cap == 256, "cap 256")?;
    assert(t.max_size == 256, "max 256")?;
    hpack_table_resize(t, 0);
    assert(t.cap == 0, "cap 0")?;
    assert(t.size == 0, "empty")?;
}

test("empty header block decodes to zero fields") {
    let raw: Vec<byte> = Vec::new();
    let g = match decode_header_block(raw) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "empty",
    };
    assert(g.count() == 0, "none")?;
}

test("POST path index.html https use static indices") {
    let h = Headers::new();
    h.add(":method", "POST");
    h.add(":path", "/index.html");
    h.add(":scheme", "https");
    let block = encode_header_block(h);
    assert(len(block) == 3, "three indexed")?;
    assert((block[0] as int) == 131, "index 3")?;
    assert((block[1] as int) == 133, "index 5")?;
    assert((block[2] as int) == 135, "index 7")?;
    let g = match decode_header_block(block) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode post",
    };
    assert(g.count() == 3, "three")?;
    assert(g.value_at(0) == "POST", "POST")?;
    assert(g.value_at(1) == "/index.html", "index.html")?;
    assert(g.value_at(2) == "https", "https")?;
}

test("literal with static name index custom value") {
    let h = Headers::new();
    h.add(":method", "PUT");
    h.add(":authority", "example.com");
    let block = encode_header_block(h);
    assert((block[0] as int) == 66, "method name idx 2 incremental")?;
    let g = match decode_header_block(block) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode name idx",
    };
    assert(g.count() == 2, "two")?;
    assert(g.name_at(0) == ":method", "method")?;
    assert(g.value_at(0) == "PUT", "PUT")?;
    assert(g.name_at(1) == ":authority", "authority")?;
    assert(g.value_at(1) == "example.com", "host")?;
}

test("content-length name index fits 6-bit incremental prefix") {
    let h = Headers::new();
    h.add("content-length", "12");
    let block = encode_header_block(h);
    // Index 28 with 6-bit prefix: 01 011100 = 92.
    assert((block[0] as int) == 92, "name idx 28 incremental")?;
    let g = match decode_header_block(block) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode cl",
    };
    assert(g.name_at(0) == "content-length", "cl")?;
    assert(g.value_at(0) == "12", "12")?;
}

test("indexed status 204 uses static index 9") {
    let raw = hpack_octets(137);
    let g = match decode_header_block(raw) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "idx 9",
    };
    assert(g.count() == 1, "one")?;
    assert(g.name_at(0) == ":status", "status")?;
    assert(g.value_at(0) == "204", "204")?;
}

test("indexed zero is an error") {
    let raw = hpack_octets(128);
    let r = decode_header_block(raw);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "idx 0")?;
}

test("literal with unknown name index is an error") {
    // Name index 70 is past the static table; empty dynamic table.
    let raw = hpack_octets(15, 55, 1, 120);
    let r = decode_header_block(raw);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "unknown name idx")?;
}

test("incremental indexing then dynamic index 62") {
    // RFC 7541 C.2.1 plus indexed 62 (0xBE) of that entry.
    let raw = hpack_octets(
        64, 10, 99, 117, 115, 116, 111, 109, 45, 107, 101, 121,
        13, 99, 117, 115, 116, 111, 109, 45, 104, 101, 97, 100, 101, 114,
        190
    );
    let g = match decode_header_block(raw) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "dyn roundtrip",
    };
    assert(g.count() == 2, "two")?;
    assert(g.name_at(0) == "custom-key", "name0")?;
    assert(g.value_at(0) == "custom-header", "val0")?;
    assert(g.name_at(1) == "custom-key", "name1")?;
    assert(g.value_at(1) == "custom-header", "val1")?;
}

test("dynamic table size update to zero is empty") {
    let raw = hpack_octets(32);
    let g = match decode_header_block(raw) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "size 0",
    };
    assert(g.count() == 0, "none")?;
}

test("truncated int continuation is an error") {
    // 5-bit prefix saturated (31) with no continuation octets.
    let raw: Vec<byte> = Vec::new();
    raw.push(31 as byte);
    let r = decode_hpack_int(raw, 0, 5);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "cont missing")?;
}

test("hpack int empty buffer is an error") {
    let raw: Vec<byte> = Vec::new();
    let r = decode_hpack_int(raw, 0, 5);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "empty")?;
}

test("hpack int exact prefix max uses continuation") {
    let out: Vec<byte> = Vec::new();
    encode_hpack_int(out, 31, 5, 0);
    assert(len(out) == 2, "two bytes")?;
    assert((out[0] as int) == 31, "prefix")?;
    assert((out[1] as int) == 0, "zero rem")?;
    let d = match decode_hpack_int(out, 0, 5) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode 31",
    };
    assert(d.value == 31, "31")?;
}

test("rfc C.4.1 huffman request block") {
    let raw = hpack_octets(
        130, 134, 132, 65, 140, 241, 227, 194, 229, 242, 58, 107, 160, 171, 144, 244, 255
    );
    let g = match decode_header_block(raw) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "C.4.1",
    };
    assert(g.count() == 4, "four")?;
    assert(g.name_at(0) == ":method", "method")?;
    assert(g.value_at(0) == "GET", "GET")?;
    assert(g.name_at(1) == ":scheme", "scheme")?;
    assert(g.value_at(1) == "http", "http")?;
    assert(g.name_at(2) == ":path", "path")?;
    assert(g.value_at(2) == "/", "slash")?;
    assert(g.name_at(3) == ":authority", "authority")?;
    assert(g.value_at(3) == "www.example.com", "host")?;
}

test("rfc C.3 dynamic table persists across blocks") {
    let t = HpackTable::new(4096);
    let first = hpack_octets(
        130, 134, 132, 65, 15, 119, 119, 119, 46, 101, 120, 97, 109, 112, 108, 101, 46, 99, 111, 109
    );
    let g1 = match decode_header_block_with(first, t) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "C.3.1",
    };
    assert(g1.value_at(3) == "www.example.com", "c31 host")?;
    let second = hpack_octets(130, 134, 132, 190, 88, 8, 110, 111, 45, 99, 97, 99, 104, 101);
    let g2 = match decode_header_block_with(second, t) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "C.3.2",
    };
    assert(g2.count() == 5, "five")?;
    assert(g2.name_at(3) == ":authority", "auth")?;
    assert(g2.value_at(3) == "www.example.com", "host")?;
    assert(g2.name_at(4) == "cache-control", "cc")?;
    assert(g2.value_at(4) == "no-cache", "no-cache")?;
}

test("rfc C.5.1 response date location cache-control") {
    let raw = hpack_octets(
        72, 3, 51, 48, 50, 88, 7, 112, 114, 105, 118, 97, 116, 101, 97, 29,
        77, 111, 110, 44, 32, 50, 49, 32, 79, 99, 116, 32, 50, 48, 49, 51,
        32, 50, 48, 58, 49, 51, 58, 50, 49, 32, 71, 77, 84, 110, 23, 104,
        116, 116, 112, 115, 58, 47, 47, 119, 119, 119, 46, 101, 120, 97, 109,
        112, 108, 101, 46, 99, 111, 109
    );
    let g = match decode_header_block(raw) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "C.5.1",
    };
    assert(g.count() == 4, "four")?;
    assert(g.name_at(0) == ":status", "status")?;
    assert(g.value_at(0) == "302", "302")?;
    assert(g.name_at(1) == "cache-control", "cc")?;
    assert(g.value_at(1) == "private", "private")?;
    assert(g.name_at(2) == "date", "date")?;
    assert(g.value_at(2) == "Mon, 21 Oct 2013 20:13:21 GMT", "gmt")?;
    assert(g.name_at(3) == "location", "loc")?;
    assert(g.value_at(3) == "https://www.example.com", "url")?;
}

test("rfc C.5.2 evicts when table cap is 256") {
    let t = HpackTable::new(256);
    let first = hpack_octets(
        72, 3, 51, 48, 50, 88, 7, 112, 114, 105, 118, 97, 116, 101, 97, 29,
        77, 111, 110, 44, 32, 50, 49, 32, 79, 99, 116, 32, 50, 48, 49, 51,
        32, 50, 48, 58, 49, 51, 58, 50, 49, 32, 71, 77, 84, 110, 23, 104,
        116, 116, 112, 115, 58, 47, 47, 119, 119, 119, 46, 101, 120, 97, 109,
        112, 108, 101, 46, 99, 111, 109
    );
    match decode_header_block_with(first, t) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "C.5.1 for eviction",
    };
    let second = hpack_octets(72, 3, 51, 48, 55, 193, 192, 191);
    let g = match decode_header_block_with(second, t) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "C.5.2",
    };
    assert(g.count() == 4, "four")?;
    assert(g.value_at(0) == "307", "307")?;
    assert(g.name_at(1) == "cache-control", "cc")?;
    assert(g.value_at(1) == "private", "private")?;
    assert(g.name_at(2) == "date", "date")?;
    assert(g.name_at(3) == "location", "loc")?;
}

test("never indexed literal decodes") {
    let raw = hpack_octets(16, 8, 112, 97, 115, 115, 119, 111, 114, 100, 6, 115, 101, 99, 114, 101, 116);
    let g = match decode_header_block(raw) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "never indexed",
    };
    assert(g.count() == 1, "one")?;
    assert(g.name_at(0) == "password", "name")?;
    assert(g.value_at(0) == "secret", "secret")?;
}

test("static table has server date location cache-control") {
    let raw = hpack_octets(182, 161, 174, 152);
    let g = match decode_header_block(raw) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "static names",
    };
    assert(g.count() == 4, "four")?;
    assert(g.name_at(0) == "server", "server")?;
    assert(g.name_at(1) == "date", "date")?;
    assert(g.name_at(2) == "location", "loc")?;
    assert(g.name_at(3) == "cache-control", "cc")?;
}

test("huffman padding zeros are an error") {
    let raw = hpack_octets(129, 0);
    let r = decode_hpack_string(raw, 0);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "bad pad")?;
}

test("size update after a field is an error") {
    let raw = hpack_octets(130, 32);
    let r = decode_header_block(raw);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "late size update")?;
}

test("encode incremental then dynamic index 62") {
    let t = HpackTable::new(4096);
    let h1 = Headers::new();
    h1.add("x-trace", "abc");
    let first = encode_header_block_with(h1, t);
    assert((first[0] as int) == 64, "incremental")?;
    assert(t.size > 0, "inserted")?;
    let h2 = Headers::new();
    h2.add("x-trace", "abc");
    let second = encode_header_block_with(h2, t);
    assert(len(second) == 1, "one octet")?;
    assert((second[0] as int) == 190, "index 62")?;
    let g = match decode_header_block_with(second, t) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode idx 62",
    };
    assert(g.count() == 1, "one")?;
    assert(g.name_at(0) == "x-trace", "name")?;
    assert(g.value_at(0) == "abc", "value")?;
}

test("rfc C.4 encode reuses authority as index 62") {
    let t = HpackTable::new(4096);
    let h1 = Headers::new();
    h1.add(":method", "GET");
    h1.add(":scheme", "http");
    h1.add(":path", "/");
    h1.add(":authority", "www.example.com");
    let first = encode_header_block_with(h1, t);
    let want1 = hpack_octets(
        130, 134, 132, 65, 140, 241, 227, 194, 229, 242, 58, 107, 160, 171, 144, 244, 255
    );
    assert(len(first) == len(want1), "C.4.1 len")?;
    let i = 0;
    while i < len(want1) {
        assert((first[i] as int) == (want1[i] as int), "C.4.1 byte")?;
        i = i + 1;
    }
    let h2 = Headers::new();
    h2.add(":method", "GET");
    h2.add(":scheme", "http");
    h2.add(":path", "/");
    h2.add(":authority", "www.example.com");
    h2.add("cache-control", "no-cache");
    let second = encode_header_block_with(h2, t);
    let want2 = hpack_octets(130, 134, 132, 190, 88, 134, 168, 235, 16, 100, 156, 255);
    assert(len(second) == len(want2), "C.4.2 len")?;
    i = 0;
    while i < len(want2) {
        assert((second[i] as int) == (want2[i] as int), "C.4.2 byte")?;
        i = i + 1;
    }
    let fresh = decode_header_block_with(second, HpackTable::new(4096));
    assert(match fresh {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "fresh table misses 62")?;
    let peer = HpackTable::new(4096);
    match decode_header_block_with(first, peer) {
        Result::Ok(_) => 0,
        Result::Err(_) => panic "peer C.4.1",
    };
    let g2 = match decode_header_block_with(second, peer) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "peer C.4.2",
    };
    assert(g2.count() == 5, "five")?;
    assert(g2.value_at(3) == "www.example.com", "host")?;
    assert(g2.value_at(4) == "no-cache", "no-cache")?;
}

test("encode eviction after table size 0 drops dynamic index") {
    let t = HpackTable::new(4096);
    let h1 = Headers::new();
    h1.add("x-trace", "abc");
    encode_header_block_with(h1, t);
    assert(t.size > 0, "had entry")?;
    hpack_table_resize(t, 0);
    assert(t.size == 0, "evicted")?;
    let h2 = Headers::new();
    h2.add("x-trace", "abc");
    let second = encode_header_block_with(h2, t);
    assert((second[0] as int) == 64, "incremental again")?;
    assert((second[0] as int) != 190, "not idx 62")?;
    let stale = hpack_octets(190);
    let r = decode_header_block_with(stale, t);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "idx 62 gone")?;
}
