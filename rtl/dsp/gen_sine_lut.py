"""Generate fpga/src/sine_lut.mem — a precomputed 4096 × 14-bit sine LUT.

Run from the repo root:
    python fpga/scripts/gen_sine_lut.py
"""

import math
import os

LUT_DEPTH = 4096
SAMPLE_WIDTH = 14
FULL_SCALE = (1 << (SAMPLE_WIDTH - 1)) - 1   # 8191

out_path = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "src", "sine_lut.mem"
)

with open(out_path, "w") as f:
    for i in range(LUT_DEPTH):
        val = int(round(math.sin(2 * math.pi * i / LUT_DEPTH) * FULL_SCALE))
        # Convert to SAMPLE_WIDTH-bit two's complement, then write as hex
        if val < 0:
            val = (1 << SAMPLE_WIDTH) + val
        f.write("{:04X}\n".format(val & ((1 << SAMPLE_WIDTH) - 1)))

print("Wrote {} entries to {}".format(LUT_DEPTH, out_path))
