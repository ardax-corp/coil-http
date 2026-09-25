#!/usr/bin/env python3
"""Separate-process delayed HTTP/1 and h2c servers for COI-408.

Binds 127.0.0.1:port, accepts one connection, waits, then responds so the
client's first recv hits EAGAIN and poll reports POLLIN.
"""
from __future__ import annotations

import argparse
import socket
import struct
import time


def frame(typ: int, flags: int, stream_id: int, payload: bytes = b"") -> bytes:
    return struct.pack("!I", len(payload))[1:] + bytes([typ, flags]) + struct.pack(
        "!I", stream_id
    ) + payload


def serve_h1(sock: socket.socket, delay: float) -> None:
    conn, _ = sock.accept()
    conn.settimeout(2.0)
    try:
        conn.recv(65536)
    except socket.timeout:
        pass
    time.sleep(delay)
    conn.sendall(
        b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"
    )
    conn.close()


def serve_h2(sock: socket.socket, delay: float) -> None:
    preface = b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
    conn, _ = sock.accept()
    conn.settimeout(2.0)
    buf = b""
    while len(buf) < len(preface):
        try:
            chunk = conn.recv(4096)
        except socket.timeout:
            break
        if not chunk:
            break
        buf += chunk
    time.sleep(delay)
    conn.sendall(frame(4, 0, 0))
    try:
        conn.recv(65536)
    except socket.timeout:
        pass
    conn.sendall(frame(4, 1, 0))
    conn.sendall(frame(1, 0x4, 1, b"\x88"))
    conn.sendall(frame(0, 0x1, 1, b"ok"))
    conn.close()


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("mode", choices=("h1", "h2"))
    p.add_argument("port", type=int)
    p.add_argument("--delay", type=float, default=0.15)
    args = p.parse_args()
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", args.port))
    s.listen(1)
    if args.mode == "h1":
        serve_h1(s, args.delay)
    else:
        serve_h2(s, args.delay)
    s.close()


if __name__ == "__main__":
    main()
