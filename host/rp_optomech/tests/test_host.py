"""WP-3 acceptance: exercise BoardSession / StreamReader / FeedbackController
end-to-end against an in-process fake daemon (no hardware).

Run:  pytest host/rp_optomech/tests/
"""

import numpy as np
import pytest

import registers_core as regs
from rp_optomech.board import BoardSession
from rp_optomech.stream import StreamReader
from rp_optomech.feedback import Channel, FeedbackController
from fake_daemon import FakeDaemon


@pytest.fixture
def board():
    fake = FakeDaemon(regs)
    b = BoardSession("127.0.0.1", regs, port=fake.port, start=False)
    yield b, fake
    b.close()
    fake.close()


def test_magic_and_ping(board):
    b, _ = board
    assert b.read("magic") == 0xDEADBEEF          # const register preloaded
    assert b.read("buffer_depth") == 0x400


def test_scratch_roundtrip(board):
    b, _ = board
    b.write("scratch", 0xCAFEF00D)
    assert b.read("scratch") == 0xCAFEF00D


def test_write_rejects_readonly(board):
    b, _ = board
    with pytest.raises(ValueError):
        b.write("magic", 0)          # ro/const
    with pytest.raises(ValueError):
        b.write("buffer_write_ptr", 0)  # ro/input


def test_unknown_register_raises(board):
    b, _ = board
    with pytest.raises(KeyError):
        b.read("does_not_exist")


def test_field_access(board):
    b, _ = board
    b.write("control", 0)
    b.write_field("control", "dac_enable", 1)
    assert b.read_field("control", "dac_enable") == 1
    assert b.read_field("control", "sys_enable") == 0
    # writing another field must not clobber the first
    b.write_field("control", "sys_enable", 1)
    assert b.read_field("control", "dac_enable") == 1
    assert b.read("control") == 0x3


def test_input_register_injection(board):
    b, fake = board
    off = regs.REGISTERS["meas_count_ch0"]["offset"]
    fake.set_input(off, 12345)
    assert b.read("meas_count_ch0") == 12345


def test_stream_reader_drains_buffer(board):
    b, fake = board
    # depth 1024, 4 words/record. Preload a couple of records at the tail.
    depth = b.read("buffer_depth")
    sr = StreamReader(b, sbuf_base=0x40020000)
    assert sr.depth == depth
    # write_ptr = 2 → two records at slots 0,1 are "most recent"
    fake.set_input(regs.REGISTERS["buffer_write_ptr"]["offset"], 2)
    for slot, vals in [(0, (10, 11, 12, 13)), (1, (20, 21, 22, 23))]:
        for w, v in enumerate(vals):
            fake.set_bram(0x40020000 + (slot * 4 + w) * 4, v)
    recs = sr.read_recent(2)
    assert len(recs) == 2
    assert list(recs["freq_raw"]) == [10, 20]
    assert list(recs["amp_dec"]) == [13, 23]


def test_feedback_controller_monitor_mode(board):
    b, fake = board
    # Inject fixed measurements for two channels.
    fake.set_input(regs.REGISTERS["meas_count_ch0"]["offset"], 1000)
    fake.set_input(regs.REGISTERS["meas_count_ch1"]["offset"], 2000)
    fake.set_input(regs.REGISTERS["lock_status_ch0"]["offset"], 1)
    chans = [
        Channel("c0", b, "meas_count_ch0", "pid_setpoint_ch0", "lock_status_ch0"),
        Channel("c1", b, "meas_count_ch1", "pid_setpoint_ch1", "lock_status_ch1"),
    ]
    fc = FeedbackController(chans, K=None)  # K=0 → monitor only
    out = fc.run([1000, 2000], duration_s=0.05, rate_hz=100.0, verbose=False)
    assert out["measured"].shape[1] == 2
    assert np.allclose(out["measured"][:, 0], 1000)
    assert out["locked"][:, 0].max() == 1
    # monitor mode leaves setpoints untouched (still 0 from reset)
    assert b.read("pid_setpoint_ch0") == 0


def test_feedback_controller_writes_setpoints_with_coupling(board):
    b, fake = board
    fake.set_input(regs.REGISTERS["meas_count_ch0"]["offset"], 900)   # 100 below target
    fake.set_input(regs.REGISTERS["meas_count_ch1"]["offset"], 2000)
    chans = [
        Channel("c0", b, "meas_count_ch0", "pid_setpoint_ch0"),
        Channel("c1", b, "meas_count_ch1", "pid_setpoint_ch1"),
    ]
    K = np.diag([1.0, 1.0])  # proportional host correction
    fc = FeedbackController(chans, K=K)
    fc.run([1000, 2000], duration_s=0.03, rate_hz=100.0, verbose=False)
    # ch0 error = +100, K diagonal 1 → setpoint written = target + 100 = 1100
    assert b.read("pid_setpoint_ch0") == 1100
    assert b.read("pid_setpoint_ch1") == 2000
