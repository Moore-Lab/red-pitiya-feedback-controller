"""Generate fpga/src/fir_coeffs.mem — 16-tap CIC compensation FIR.

Frequency-sampling design: we sample 1 / H_CIC(f) on a sparse frequency grid
across the decimated passband, build a conjugate-symmetric spectrum with linear
phase, IFFT, Hann-window, and quantise to Q1.15 (signed 16-bit, DC gain = 1).

Run anywhere with numpy (no scipy needed):
    python3 fpga/scripts/gen_fir_coeffs.py
"""

import math
import os

import numpy as np


# CIC parameters (must match cic_decimator.v)
R = 10
N = 4

# FIR design
NTAPS = 16
COEFF_WIDTH = 16
SCALE = 1 << (COEFF_WIDTH - 1)   # 32768 (Q1.15)

# Cap the maximum inverse gain to avoid wild values near the CIC nulls.
MAX_BOOST = 3.0


def cic_gain(f_norm_in):
    """Magnitude response of an Nth-order CIC, M=1, normalised to DC = 1."""
    if f_norm_in == 0.0:
        return 1.0
    num = math.sin(math.pi * R * f_norm_in)
    den = R * math.sin(math.pi * f_norm_in)
    if den == 0.0:
        return 0.0
    return abs(num / den) ** N


# Target response sampled at NTAPS/2+1 evenly-spaced points across the FIR's
# real spectrum (DC to decimated Nyquist).
H_target = np.zeros(NTAPS // 2 + 1)
for k in range(NTAPS // 2 + 1):
    f_norm_dec = k / NTAPS        # 0, 1/16, 2/16, ..., 8/16 of decimated rate
    f_norm_in  = f_norm_dec / R   # convert back to fraction of input fs
    g = cic_gain(f_norm_in)
    if g < 1.0 / MAX_BOOST:
        H_target[k] = MAX_BOOST
    else:
        H_target[k] = 1.0 / g

# Build conjugate-symmetric spectrum with linear phase that centres the
# impulse response in the middle of the tap window.
H_full = np.zeros(NTAPS, dtype=complex)
H_full[0]            = H_target[0]
H_full[NTAPS // 2]   = H_target[NTAPS // 2] * np.exp(-1j * np.pi * (NTAPS - 1) / 2)
for k in range(1, NTAPS // 2):
    phase = np.exp(-1j * 2 * np.pi * k * (NTAPS - 1) / (2 * NTAPS))
    H_full[k]         = H_target[k] * phase
    H_full[NTAPS - k] = np.conj(H_full[k])

# IFFT → impulse response
h = np.real(np.fft.ifft(H_full))

# Hann window to suppress ringing
win = 0.5 * (1 - np.cos(2 * np.pi * np.arange(NTAPS) / (NTAPS - 1)))
h_win = h * win

# Normalise so DC gain (= sum of coefficients) is exactly 1.0
h_norm = h_win / np.sum(h_win)

# Quantise to Q1.15
h_int = np.round(h_norm * SCALE).astype(int)
h_int = np.clip(h_int, -SCALE, SCALE - 1)
# Touch up centre tap so the integer sum is exactly SCALE
correction = SCALE - int(np.sum(h_int))
h_int[NTAPS // 2 - 1] += correction

# Verify response at a few key frequencies
def fir_gain(h_int, f_norm_dec):
    g = 0.0
    for n, c in enumerate(h_int):
        g += c * math.cos(2 * math.pi * f_norm_dec * (n - (NTAPS - 1) / 2))
    return g / SCALE

print("FIR coefficients (Q1.{}):".format(COEFF_WIDTH - 1))
for i, c in enumerate(h_int):
    print("  h[{:2d}] = {:6d}  ({:+.4f})".format(i, c, c / SCALE))
print("Sum = {} (target {})".format(int(np.sum(h_int)), SCALE))
print()
print("Combined CIC + FIR gain at key frequencies:")
for f_dec in [0.0, 0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.4]:
    f_in = f_dec / R
    cic_db = 20 * math.log10(cic_gain(f_in)) if cic_gain(f_in) > 0 else float("-inf")
    fir_db = 20 * math.log10(abs(fir_gain(h_int, f_dec))) if fir_gain(h_int, f_dec) > 0 else float("-inf")
    total_db = cic_db + fir_db
    print("  f_dec={:.2f}/Nyq  CIC={:+.2f}dB  FIR={:+.2f}dB  total={:+.2f}dB".format(
        f_dec * 2, cic_db, fir_db, total_db))

# Write .mem file
out_path = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "src", "fir_coeffs.mem",
)

with open(out_path, "w") as f:
    for c in h_int:
        val = int(c) & ((1 << COEFF_WIDTH) - 1)
        f.write("{:04X}\n".format(val))

print("\nWrote {} coefficients to {}".format(NTAPS, out_path))
