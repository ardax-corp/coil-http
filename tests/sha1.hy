// SHA-1 handshake helper (RFC 3174 vectors).
use string::{to_bytes};
use http::sha1::{sha1};

fn expect_byte(Vec<byte> d, int i, int want, string tag) {
    if d[i] as int != want {
        panic tag;
    }
}

test("sha1 empty") {
    let empty: Vec<byte> = Vec::new();
    let d = sha1(empty);
    assert(len(d) == 20, "digest len")?;
    // da39a3ee5e6b4b0d3255bfef95601890afd80709
    expect_byte(d, 0, 218, "e0");
    expect_byte(d, 1, 57, "e1");
    expect_byte(d, 2, 163, "e2");
    expect_byte(d, 19, 9, "e19");
}

test("sha1 abc") {
    let d = sha1(to_bytes("abc"));
    // a9993e364706816aba3e25717850c26c9cd0d89d
    expect_byte(d, 0, 169, "a0");
    expect_byte(d, 1, 153, "a1");
    expect_byte(d, 2, 62, "a2");
    expect_byte(d, 3, 54, "a3");
    expect_byte(d, 19, 157, "a19");
}
