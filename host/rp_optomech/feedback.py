"""FeedbackController — an N-channel, multi-board host feedback loop.

Generalises the spin-controller's host_mimo.py. You describe a set of control
channels (each bound to a board + a per-channel register group), give it a
coupling matrix K, and it runs the loop:

    measured = [ read each channel's measurement ]
    error    = target - measured
    delta    = K @ error                     # cross-channel coupling
    write updated setpoints (target + delta)

K = 0 (the default) makes it a pure monitor: the per-channel on-PL PIDs run
untouched and the host just logs. Off-diagonal terms in K implement MIMO
cross-axis feedback (e.g. COM-mode coupling in a nanosphere trap), calibrated
from impulse-response experiments.

This is deliberately a skeleton: the measurement-to-physical-units conversion
and the setpoint encoding are experiment-specific and passed in as callables.
"""

from __future__ import print_function

import time

import numpy as np


class Channel(object):
    """One control channel: a board + the register names for its lane."""

    def __init__(self, name, board, meas_reg, setpoint_reg,
                 lock_reg=None, meas_to_hz=None, hz_to_setpoint=None):
        self.name = name
        self.board = board
        self.meas_reg = meas_reg
        self.setpoint_reg = setpoint_reg
        self.lock_reg = lock_reg
        # Conversions default to identity; override per experiment.
        self.meas_to_hz = meas_to_hz or (lambda counts: float(counts))
        self.hz_to_setpoint = hz_to_setpoint or (lambda hz: int(round(hz)))

    def read_measurement(self):
        return self.meas_to_hz(self.board.read(self.meas_reg))

    def read_locked(self):
        if self.lock_reg is None:
            return False
        return bool(self.board.read(self.lock_reg) & 1)

    def write_setpoint(self, hz):
        self.board.write(self.setpoint_reg, self.hz_to_setpoint(hz) & 0xFFFFFFFF)


class FeedbackController(object):
    def __init__(self, channels, K=None):
        self.channels = list(channels)
        n = len(self.channels)
        self.K = np.zeros((n, n)) if K is None else np.asarray(K, dtype=float)
        if self.K.shape != (n, n):
            raise ValueError("K must be {0}x{0} for {0} channels".format(n))

    def run(self, targets_hz, duration_s, rate_hz=100.0, log=None, verbose=True):
        """Run the coupled loop. `targets_hz` is one setpoint per channel."""
        target = np.asarray(targets_hz, dtype=float)
        n = len(self.channels)
        n_iter = int(duration_s * rate_hz)
        period = 1.0 / rate_hz

        t_log = np.empty(n_iter)
        meas_log = np.empty((n_iter, n))
        set_log = np.empty((n_iter, n))
        lock_log = np.zeros((n_iter, n), dtype=np.int8)

        t0 = time.time()
        for i in range(n_iter):
            t = time.time() - t0
            measured = np.array([c.read_measurement() for c in self.channels])
            locked = np.array([c.read_locked() for c in self.channels], dtype=np.int8)

            error = target - measured
            delta = self.K.dot(error)
            if np.any(delta != 0):
                for c, sp in zip(self.channels, target + delta):
                    c.write_setpoint(sp)

            t_log[i] = t
            meas_log[i] = measured
            set_log[i] = target + delta
            lock_log[i] = locked

            if verbose and i % max(1, int(rate_hz)) == 0:
                print("t={:6.2f}s  " .format(t)
                      + "  ".join("{}={:.3e}".format(c.name, m)
                                  for c, m in zip(self.channels, measured)))

            wait = (i + 1) * period - (time.time() - t0)
            if wait > 0:
                time.sleep(wait)

        if log:
            np.savez(log, t=t_log, measured=meas_log, setpoint=set_log,
                     locked=lock_log, target=target, K=self.K)
        return dict(t=t_log, measured=meas_log, setpoint=set_log, locked=lock_log)
