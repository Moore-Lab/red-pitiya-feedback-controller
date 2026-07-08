#!/usr/bin/env python3
"""rp_daemon — lightweight AXI bridge daemon for the Red Pitaya (runs on-board).

Opens /dev/mem once and serves register + BRAM access over a persistent TCP
socket, so the host can do hundreds of accesses/second (vs ~100 ms per fresh
SSH+python call). Generalises the spin-controller's axi_daemon.py: the control
and BRAM regions are configurable via CLI so the same daemon serves any design.

Protocol (text, line-oriented):
    R  <hex_off>            -> "<hex_value>"          read a control register
    W  <hex_off> <hex_val>  -> "OK"                   write a control register
    RB <hex_off> <count>    -> "<hv0> <hv1> ..."      read N words from the BRAM region
    PING                    -> "PONG"
    QUIT                    -> daemon exits

Usage on the Pitaya (Python 3.5+):
    python3 rp_daemon.py --port 9001 \
        --ctrl-base 0x40000000 --ctrl-size 0x1000 \
        --bram-base 0x40020000 --bram-size 0x4000
"""

from __future__ import print_function

import argparse
import mmap
import os
import socket
import struct
import sys


def serve(port, ctrl_base, ctrl_size, bram_base, bram_size):
    fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
    ctrl = mmap.mmap(fd, ctrl_size, mmap.MAP_SHARED,
                     mmap.PROT_READ | mmap.PROT_WRITE, offset=ctrl_base)
    bram = mmap.mmap(fd, bram_size, mmap.MAP_SHARED,
                     mmap.PROT_READ, offset=bram_base) if bram_size else None
    os.close(fd)

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", port))
    srv.listen(1)
    print("rp_daemon listening on port {}".format(port))

    while True:
        conn, addr = srv.accept()
        try:
            f = conn.makefile("rwb", buffering=0)
            for raw in f:
                line = raw.decode("ascii", errors="replace").strip()
                if not line:
                    continue
                try:
                    out = handle(line, ctrl, bram)
                except Exception as e:
                    out = "ERR " + str(e)
                f.write((out + "\n").encode("ascii"))
                if line.upper() == "QUIT":
                    break
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            conn.close()


def handle(line, ctrl, bram):
    parts = line.split()
    cmd = parts[0].upper()
    if cmd == "PING":
        return "PONG"
    if cmd == "QUIT":
        return "BYE"
    if cmd == "R":
        off = int(parts[1], 16)
        return "{:08x}".format(struct.unpack("<I", ctrl[off:off + 4])[0])
    if cmd == "W":
        off = int(parts[1], 16)
        val = int(parts[2], 16) & 0xFFFFFFFF
        ctrl[off:off + 4] = struct.pack("<I", val)
        return "OK"
    if cmd == "RB":
        if bram is None:
            return "ERR no BRAM region configured"
        off = int(parts[1], 16)
        count = int(parts[2], 10)
        words = struct.unpack("<{}I".format(count), bram[off:off + 4 * count])
        return " ".join("{:08x}".format(w) for w in words)
    return "ERR unknown command " + cmd


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--port", type=int, default=9001)
    p.add_argument("--ctrl-base", type=lambda s: int(s, 0), default=0x40000000)
    p.add_argument("--ctrl-size", type=lambda s: int(s, 0), default=0x1000)
    p.add_argument("--bram-base", type=lambda s: int(s, 0), default=0x40020000)
    p.add_argument("--bram-size", type=lambda s: int(s, 0), default=0x4000)
    args = p.parse_args()
    try:
        serve(args.port, args.ctrl_base, args.ctrl_size, args.bram_base, args.bram_size)
    except KeyboardInterrupt:
        print("interrupted")
    return 0


if __name__ == "__main__":
    sys.exit(main())
