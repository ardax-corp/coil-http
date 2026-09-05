// Pure-Coil SHA-1 (RFC 3174) for the WebSocket handshake only.
// coil-crypto has SHA-256/512/BLAKE3, not SHA-1; no HostInvoke.

fn sha1_mod256() -> int {
    return 128 + 128;
}

fn sha1_b24() -> int {
    let m = sha1_mod256();
    return m * m * m;
}

fn sha1_mask() -> int {
    return sha1_b24() * sha1_mod256() - 1;
}

fn sha1_u8(int n) -> byte {
    let m = sha1_mod256();
    return (n % m) as byte;
}

fn sha1_mod32() -> int {
    return sha1_mask() + 1;
}

fn sha1_u32(int n) -> int {
    let m = sha1_mod32();
    while n < 0 {
        n = n + m;
    }
    return n % m;
}

fn sha1_and(int a, int b) -> int {
    a = sha1_u32(a);
    b = sha1_u32(b);
    let r = 0;
    let p = 1;
    let i = 0;
    let w = 8 + 8 + 8 + 8;
    while i < w {
        if (a / p) % 2 == 1 {
            if (b / p) % 2 == 1 {
                r = r + p;
            }
        }
        p = p + p;
        i = i + 1;
    }
    return r;
}

fn sha1_or(int a, int b) -> int {
    return sha1_u32(a + b - sha1_and(a, b));
}

fn sha1_xor(int a, int b) -> int {
    return sha1_u32(a + b - sha1_and(a, b) - sha1_and(a, b));
}

fn sha1_rotl(int n, int k) -> int {
    n = sha1_u32(n);
    let w = 8 + 8 + 8 + 8;
    return sha1_u32((n << k) | (n >> (w - k)));
}

fn sha1_add2(int a, int b) -> int {
    return sha1_u32(a + b);
}

fn sha1_add5(int a, int b, int c, int d, int e) -> int {
    return sha1_u32(a + b + c + d + e);
}

fn sha1_not(int n) -> int {
    return sha1_mask() - sha1_u32(n);
}

fn sha1_from_be(int b0, int b1, int b2, int b3) -> int {
    let m = sha1_mod256();
    return sha1_u32(((b0 * m + b1) * m + b2) * m + b3);
}

fn sha1_k(int t) -> int {
    if t < 20 {
        return sha1_from_be(90, 130, 121, 153);
    }
    if t < 40 {
        return sha1_from_be(110, 217, 235, 161);
    }
    if t < 60 {
        return sha1_from_be(143, 27, 188, 220);
    }
    return sha1_from_be(202, 98, 193, 214);
}

fn sha1_f(int t, int b, int c, int d) -> int {
    if t < 20 {
        return sha1_or(sha1_and(b, c), sha1_and(sha1_not(b), d));
    }
    if t < 40 {
        return sha1_xor(sha1_xor(b, c), d);
    }
    if t < 60 {
        return sha1_or(sha1_or(sha1_and(b, c), sha1_and(b, d)), sha1_and(c, d));
    }
    return sha1_xor(sha1_xor(b, c), d);
}

fn sha1_push_u32be(Vec<byte> out, int n) {
    n = sha1_u32(n);
    let m = sha1_mod256();
    out.push(sha1_u8(n / sha1_b24()));
    out.push(sha1_u8(n / (m * m)));
    out.push(sha1_u8(n / m));
    out.push(sha1_u8(n));
}

fn sha1_word_be(Vec<byte> b, int i) -> int {
    return sha1_u32(
        ((b[i] as int) << 24)
        | ((b[i + 1] as int) << 16)
        | ((b[i + 2] as int) << 8)
        | (b[i + 3] as int)
    );
}

fn sha1_pad(Vec<byte> msg) -> Vec<byte> {
    let out: Vec<byte> = Vec::new();
    let i = 0;
    while i < len(msg) {
        out.push(msg[i]);
        i = i + 1;
    }
    let bitlen = len(msg) * 8;
    out.push(128);
    while (len(out) % 64) != 56 {
        out.push(0);
    }
    out.push(0);
    out.push(0);
    out.push(0);
    out.push(0);
    sha1_push_u32be(out, bitlen);
    return out;
}

fn sha1_process_block(Vec<int> h, Vec<byte> block, int off) {
    let w: Vec<int> = Vec::new();
    let t = 0;
    while t < 80 {
        w.push(0);
        t = t + 1;
    }
    t = 0;
    while t < 16 {
        w[t] = sha1_word_be(block, off + t * 4);
        t = t + 1;
    }
    while t < 80 {
        w[t] = sha1_rotl(sha1_xor(sha1_xor(sha1_xor(w[t - 3], w[t - 8]), w[t - 14]), w[t - 16]), 1);
        t = t + 1;
    }
    let a = h[0];
    let b = h[1];
    let c = h[2];
    let d = h[3];
    let e = h[4];
    t = 0;
    while t < 80 {
        let temp = sha1_add5(sha1_rotl(a, 5), sha1_f(t, b, c, d), e, sha1_k(t), w[t]);
        e = d;
        d = c;
        c = sha1_rotl(b, 30);
        b = a;
        a = temp;
        t = t + 1;
    }
    h[0] = sha1_add2(h[0], a);
    h[1] = sha1_add2(h[1], b);
    h[2] = sha1_add2(h[2], c);
    h[3] = sha1_add2(h[3], d);
    h[4] = sha1_add2(h[4], e);
}

/// SHA-1 digest (20 bytes, big-endian).
fn sha1(Vec<byte> msg) -> Vec<byte> {
    let h: Vec<int> = Vec::new();
    h.push(sha1_from_be(103, 69, 35, 1));
    h.push(sha1_from_be(239, 205, 171, 137));
    h.push(sha1_from_be(152, 186, 220, 254));
    h.push(sha1_from_be(16, 50, 84, 118));
    h.push(sha1_from_be(195, 210, 225, 240));
    let padded = sha1_pad(msg);
    let off = 0;
    while off < len(padded) {
        sha1_process_block(h, padded, off);
        off = off + 64;
    }
    let out: Vec<byte> = Vec::new();
    sha1_push_u32be(out, h[0]);
    sha1_push_u32be(out, h[1]);
    sha1_push_u32be(out, h[2]);
    sha1_push_u32be(out, h[3]);
    sha1_push_u32be(out, h[4]);
    return out;
}
