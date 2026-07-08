"""WP-4 acceptance check: the generated spin_controller register map must exactly
reproduce the hand-written instrument's addresses.

REFERENCE is transcribed independently from the source repo's
docs/implementation_status.md register table (offsets 0x00..0xA4, 42 registers).
This asserts the spec ordering + the allocator + the generators reproduce it with
no gaps, overlaps, or drift.

Run:  python examples/spin_controller/verify_offsets.py
"""

import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "regspec"))
sys.path.insert(0, os.path.join(ROOT, "host", "rp_optomech"))

# Ground truth: (name, offset, access) from implementation_status.md section 3.
REFERENCE = [
    ("control",             0x00, "rw"),
    ("blink_half_period",   0x04, "rw"),
    ("scratch",             0x08, "rw"),
    ("magic",               0x0C, "ro"),
    ("nco_tuning_word",     0x10, "rw"),
    ("nco_amplitude",       0x14, "rw"),
    ("capture_ctrl",        0x18, "rw"),
    ("capture_status",      0x1C, "ro"),
    ("freq_gate_cycles",    0x20, "rw"),
    ("freq_count_raw",      0x24, "ro"),
    ("freq_threshold",      0x28, "rw"),
    ("freq_count_dec",      0x2C, "ro"),
    ("amp_raw",             0x30, "ro"),
    ("amp_dec",             0x34, "ro"),
    ("buffer_enable",       0x38, "rw"),
    ("buffer_write_ptr",    0x3C, "ro"),
    ("buffer_sample_count", 0x40, "ro"),
    ("buffer_depth",        0x44, "ro"),
    ("pid_setpoint",        0x48, "rw"),
    ("pid_gains",           0x4C, "rw"),
    ("nco_shift",           0x50, "rw"),
    ("pid_output",          0x54, "ro"),
    ("pid_status",          0x58, "ro"),
    ("lock_status",         0x5C, "ro"),
    ("lock_target_tw",      0x60, "rw"),
    ("lock_ramp_rate",      0x64, "rw"),
    ("lock_capture_win",    0x68, "rw"),
    ("sync_control",        0x6C, "rw"),
    ("adc_select",          0x70, "rw"),
    ("nco_tuning_word_b",   0x74, "rw"),
    ("nco_amplitude_b",     0x78, "rw"),
    ("freq_count_dec_b",    0x7C, "ro"),
    ("amp_dec_b",           0x80, "ro"),
    ("pid_setpoint_b",      0x84, "rw"),
    ("pid_gains_b",         0x88, "rw"),
    ("nco_shift_b",         0x8C, "rw"),
    ("pid_output_b",        0x90, "ro"),
    ("pid_status_b",        0x94, "ro"),
    ("lock_status_b",       0x98, "ro"),
    ("lock_target_tw_b",    0x9C, "rw"),
    ("lock_ramp_rate_b",    0xA0, "rw"),
    ("lock_capture_win_b",  0xA4, "rw"),
]


def main():
    import regspec
    spec = regspec.load(os.path.join(ROOT, "regspec", "specs", "spin_controller.yaml"))
    got = {r.name: (r.offset, r.access) for r in spec.registers}

    errors = []
    if len(spec.registers) != len(REFERENCE):
        errors.append("count mismatch: spec has {}, reference has {}".format(
            len(spec.registers), len(REFERENCE)))

    for name, off, acc in REFERENCE:
        if name not in got:
            errors.append("missing register: {}".format(name))
            continue
        g_off, g_acc = got[name]
        if g_off != off:
            errors.append("{}: offset 0x{:02x}, expected 0x{:02x}".format(name, g_off, off))
        if g_acc != acc:
            errors.append("{}: access {}, expected {}".format(name, g_acc, acc))

    extra = set(got) - {n for n, _o, _a in REFERENCE}
    for name in sorted(extra):
        errors.append("unexpected register: {}".format(name))

    if errors:
        print("FAIL — {} discrepancy(ies):".format(len(errors)))
        for e in errors:
            print("  " + e)
        return 1
    print("PASS — all {} registers match the reference map (0x00..0x{:02x}) exactly.".format(
        len(REFERENCE), REFERENCE[-1][1]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
