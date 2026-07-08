"""StreamReader — drain the on-PL streaming ring buffer from the host.

Generalises the spin-controller's stream_reader.py. The PL writes one fixed-size
record per measurement gate into a circular BRAM; this class reads the buffer
control registers (by name, via a BoardSession) and pulls the raw words back
over the daemon's block-read command, returning a numpy structured array.

The record layout is design-specific — pass `fields` as a list of (name, dtype)
for the words in one record (defaults match the spin-controller's 4-word
(freq_raw, freq_dec, amp_raw, amp_dec) layout).
"""

from __future__ import print_function

import numpy as np

DEFAULT_FIELDS = [
    ("freq_raw", np.uint32),
    ("freq_dec", np.uint32),
    ("amp_raw", np.uint32),
    ("amp_dec", np.uint32),
]


class StreamReader(object):
    def __init__(self, board, sbuf_base=0x40020000,
                 enable_reg="buffer_enable", wptr_reg="buffer_write_ptr",
                 count_reg="buffer_sample_count", depth_reg="buffer_depth",
                 fields=None):
        self.b = board
        self.sbuf_base = sbuf_base
        self.enable_reg = enable_reg
        self.wptr_reg = wptr_reg
        self.count_reg = count_reg
        self.fields = fields or DEFAULT_FIELDS
        self.words_per_record = len(self.fields)
        depth = board.read(depth_reg) if depth_reg in board._meta else 0
        self.depth = depth if depth else 1024

    def enable(self):
        self.b.write(self.enable_reg, 1)

    def disable(self):
        self.b.write(self.enable_reg, 0)

    def write_ptr(self):
        return self.b.read(self.wptr_reg) & (self.depth - 1)

    def sample_count(self):
        return self.b.read(self.count_reg)

    def read_recent(self, n):
        """Return the n most-recent records as a numpy structured array."""
        if n > self.depth:
            n = self.depth
        wp = self.write_ptr()
        total_words = self.depth * self.words_per_record
        raw = np.array(self.b.read_bram(self.sbuf_base, total_words), dtype=np.uint32)
        records = raw.reshape(self.depth, self.words_per_record)
        start = (wp - n) % self.depth
        if start < wp:
            sel = records[start:wp]
        else:
            sel = np.concatenate([records[start:], records[:wp]], axis=0)
        out = np.empty(len(sel), dtype=self.fields)
        for i, (name, _dt) in enumerate(self.fields):
            out[name] = sel[:, i]
        return out
