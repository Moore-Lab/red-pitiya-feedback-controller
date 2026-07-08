#!/usr/bin/env python3
"""Nanosphere COM feedback — host demo (skeleton).

Shows the full host stack for a 3-axis (x/y/z) lock-in feedback controller built
on the framework: configure each axis's reference oscillator + gains, then run the
FeedbackController, reading each axis's demodulated magnitude (meas_mag) as the
error signal. Uses the GENERATED register module — no hard-coded offsets.

Wiring assumed in the FPGA design (per examples/nanosphere/README.md):
  lock_in.error_count -> meas_mag_<i>,  lock_in.i_out -> meas_i_<i>, q_out -> meas_q_<i>
  pid_setpoint_<i> -> the PID that drives meas_mag toward the setpoint (0 = cool).

This will only *run* against a board (or the test fake daemon); with no board it
still imports and builds the objects, which is what CI/py_compile checks.

Usage:
    python examples/nanosphere/host_demo.py --board 192.168.8.220 --duration 10
"""

from __future__ import print_function

import argparse
import os
import sys

# Make the framework's host package + generated register module importable.
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "host"))
sys.path.insert(0, os.path.join(ROOT, "host", "rp_optomech"))

import registers_nanosphere as regs
from rp_optomech.board import BoardSession
from rp_optomech.feedback import Channel, FeedbackController

AXES = ["0", "1", "2"]   # x, y, z
CLK_HZ = 125_000_000


def tw(freq_hz):
    return int(round(freq_hz * (1 << 32) / CLK_HZ)) & 0xFFFFFFFF


def build_channels(board):
    """One Channel per axis: error = demodulated magnitude, actuator = pid_setpoint."""
    return [
        Channel("axis_" + a, board,
                meas_reg="meas_mag_" + a,
                setpoint_reg="pid_setpoint_" + a,
                lock_reg="lock_status_" + a)
        for a in AXES
    ]


def configure(board, mode_freqs_hz, kp=0.2, ki=0.05):
    """Set each axis's lock-in reference to its mechanical mode frequency + PID gains."""
    board.write("gate_cycles", 1_250_000)     # 10 ms integration
    for a, f in zip(AXES, mode_freqs_hz):
        board.write("lockin_ref_tw_" + a, tw(f))
        board.write("drive_amplitude_" + a, 0x2000)
        board.write("pid_setpoint_" + a, 0)   # cool toward zero amplitude
        gains = ((int(round(kp * 4096)) & 0xFFFF) << 16) | (int(round(ki * 4096)) & 0xFFFF)
        board.write("pid_gains_" + a, gains)
    board.write_field("control", "sys_enable", 1)
    board.write_field("control", "dac_enable", 1)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--board", default="192.168.8.220")
    p.add_argument("--duration", type=float, default=10.0)
    p.add_argument("--rate", type=float, default=50.0)
    p.add_argument("--fx", type=float, default=120e3, help="x mode frequency (Hz)")
    p.add_argument("--fy", type=float, default=140e3, help="y mode frequency (Hz)")
    p.add_argument("--fz", type=float, default=40e3,  help="z mode frequency (Hz)")
    p.add_argument("--log", default=None)
    args = p.parse_args()

    with BoardSession(args.board, regs) as b:
        assert b.read("magic") == 0xDEADBEEF, "AXI bridge not alive"
        configure(b, [args.fx, args.fy, args.fz])
        chans = build_channels(b)
        # K = 0 -> monitor; supply a calibrated coupling matrix for real MIMO cooling.
        fc = FeedbackController(chans, K=None)
        fc.run([0, 0, 0], duration_s=args.duration, rate_hz=args.rate, log=args.log)
    return 0


if __name__ == "__main__":
    sys.exit(main())
