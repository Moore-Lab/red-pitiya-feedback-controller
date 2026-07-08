"""rp_optomech — host-side control for Red Pitaya optomechanics feedback designs.

Spec-driven: register access is by *name*, resolved through a generated
`registers_<design>.py` module (produced by `regspec/gen_all.py`), so the host
never hard-codes an offset. Pair a BoardSession with the registers module for
your design:

    from rp_optomech.board import BoardSession
    import registers_core as regs          # generated from your spec

    with BoardSession("192.168.8.220", regs) as b:
        assert b.read("magic") == 0xDEADBEEF
        b.write("nco_tuning_word_ch0", regs_tuning_word)
        b.write_field("control", "dac_enable", 1)
        f = b.read("meas_count_ch0")

The three main pieces:
  * board.py    — BoardSession: name-based AXI register + BRAM access over TCP.
  * stream.py   — StreamReader: drain the on-PL streaming ring buffer.
  * feedback.py — FeedbackController: an N-channel / multi-board loop with a
                  coupling matrix (generalises the spin-controller's host_mimo).

The board-side daemon lives in daemon.py; copy it to the Pitaya and run it.
"""

__all__ = ["board", "stream", "feedback"]
__version__ = "0.1.0"
