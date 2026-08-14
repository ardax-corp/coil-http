// HPACK static-table header block tests (no Huffman, no dynamic table).
use http::url::{Headers};
use http::hpack::{
    decode_header_block,
    decode_hpack_int,
    decode_hpack_string,
    encode_header_block,
    encode_hpack_int,
    encode_hpack_string,
};

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

test("literal without indexing new name") {
    let h = Headers::new();
    h.add("x-trace", "abc");
    let block = encode_header_block(h);
    assert((block[0] as int) == 0, "index 0")?;
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

test("huffman string is not supported") {
    let raw: Vec<byte> = Vec::new();
    raw.push(0 as byte);
    raw.push(129 as byte);
    raw.push(0 as byte);
    let r = decode_header_block(raw);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "huffman")?;
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
    assert((block[0] as int) == 2, "method name idx 2")?;
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

test("content-length name index is multi-byte prefix") {
    let h = Headers::new();
    h.add("content-length", "12");
    let block = encode_header_block(h);
    // Index 28 with 4-bit prefix: 0x0F then 13 (28 - 15).
    assert((block[0] as int) == 15, "prefix ones")?;
    assert((block[1] as int) == 13, "cont 13")?;
    let g = match decode_header_block(block) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode cl",
    };
    assert(g.name_at(0) == "content-length", "cl")?;
    assert(g.value_at(0) == "12", "12")?;
}

test("unknown indexed static field is an error") {
    // Index 9 is outside the compact Appendix A subset.
    let raw: Vec<byte> = Vec::new();
    raw.push(137 as byte);
    let r = decode_header_block(raw);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "unknown idx")?;
}

test("literal with unknown name index is an error") {
    // Name index 15 is not in the compact static subset; value is "x".
    let raw: Vec<byte> = Vec::new();
    raw.push(15 as byte);
    raw.push(1 as byte);
    raw.push(("x" as byte));
    let r = decode_header_block(raw);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "unknown name idx")?;
}

test("incremental indexing representation is not supported") {
    let raw: Vec<byte> = Vec::new();
    raw.push(64 as byte);
    let r = decode_header_block(raw);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "incremental")?;
}

test("dynamic table size update is not supported") {
    let raw: Vec<byte> = Vec::new();
    raw.push(32 as byte);
    let r = decode_header_block(raw);
    assert(match r {
        Result::Ok(_) => false,
        Result::Err(_) => true,
    }, "dyn size")?;
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
