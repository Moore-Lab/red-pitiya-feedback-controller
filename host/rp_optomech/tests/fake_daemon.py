"""In-process fake of the board-side rp_daemon, for hardware-free host tests.

Implements the same line protocol (R / W / RB / PING / QUIT) against an in-memory
register + BRAM store, so BoardSession/StreamReader/FeedbackController can be
exercised end-to-end without a Red Pitaya. Constants (magic, buffer_depth) and
read-only 'input' registers can be preloaded/injected via `set_input`.
"""

import socket
import struct
import threading


class FakeDaemon(object):
    def __init__(self, regs=None):
        self.store = {}   # control-region offset -> 32-bit value
        self.bram = {}    # bram byte-offset -> 32-bit value
        if regs is not None:
            # Preload const/reset values so magic etc. read correctly.
            for name, meta in regs.REGISTERS.items():
                if meta["access"] == "rw" or meta.get("source") == "const":
                    self.store[meta["offset"]] = meta["reset"]
        self.srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.srv.bind(("127.0.0.1", 0))
        self.srv.listen(1)
        self.port = self.srv.getsockname()[1]
        self._stop = False
        self.thread = threading.Thread(target=self._serve, daemon=True)
        self.thread.start()

    # backdoor for tests: force a read-only 'input' register / a BRAM word
    def set_input(self, offset, value):
        self.store[offset] = value & 0xFFFFFFFF

    def set_bram(self, offset, value):
        self.bram[offset] = value & 0xFFFFFFFF

    def _serve(self):
        while not self._stop:
            try:
                conn, _ = self.srv.accept()
            except OSError:
                break
            f = conn.makefile("rwb", buffering=0)
            try:
                for raw in f:
                    line = raw.decode("ascii").strip()
                    if not line:
                        continue
                    out = self._handle(line)
                    f.write((out + "\n").encode("ascii"))
                    if line.upper() == "QUIT":
                        break
            except OSError:
                pass
            finally:
                conn.close()

    def _handle(self, line):
        p = line.split()
        cmd = p[0].upper()
        if cmd == "PING":
            return "PONG"
        if cmd == "QUIT":
            return "BYE"
        if cmd == "R":
            off = int(p[1], 16)
            return "{:08x}".format(self.store.get(off, 0))
        if cmd == "W":
            off = int(p[1], 16)
            self.store[off] = int(p[2], 16) & 0xFFFFFFFF
            return "OK"
        if cmd == "RB":
            off = int(p[1], 16)
            count = int(p[2], 10)
            return " ".join("{:08x}".format(self.bram.get(off + 4 * i, 0))
                            for i in range(count))
        return "ERR unknown " + cmd

    def close(self):
        self._stop = True
        try:
            self.srv.close()
        except OSError:
            pass
