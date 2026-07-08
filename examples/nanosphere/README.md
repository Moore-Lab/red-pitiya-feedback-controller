# Example: nanosphere COM feedback controller (skeleton)

A 3-axis (x/y/z) centre-of-mass feedback controller — the framework's target "some other
experiment." **This is a skeleton**, not a built design: it shows how the pieces compose. It is
the first real downstream build (PLAN WP-7), blocked on the lock-in measurement block (WP-5) and
the block-design generator (WP-6).

## What's here
- [`../../regspec/specs/nanosphere.yaml`](../../regspec/specs/nanosphere.yaml) — the register
  spec: shared header + streaming, plus a 3-channel lane (x/y/z) with a lock-in reference
  oscillator, demodulated magnitude, and I/Q readback per axis. Generated → 36 registers.
- [`host_demo.py`](host_demo.py) — runnable host skeleton: configures each axis's reference
  frequency + PID gains and runs the `FeedbackController` reading `meas_mag_<i>` as the error.
- The measurement block it needs, [`rtl/measurement/lock_in.v`](../../rtl/measurement/lock_in.v),
  **is built and tested** (WP-5). Wire `lock_in.error_count → meas_mag_<i>`, `i_out/q_out →
  meas_i/meas_q_<i>` per axis.

## How it maps onto the framework
| Concern | Framework piece |
|---------|-----------------|
| Runtime-configurable registers | generated `nanosphere_regs.v` + `registers_nanosphere.py` |
| Measure COM motion per axis | `rtl/measurement/lock_in.v` (complete the stub — WP-5) |
| Per-axis feedback | `rtl/feedback/pid_controller.v` + `nco_summer.v` |
| Actuate feedback force | `rtl/dsp/dac_sine.v` → `rtl/io/dac_interface.v` |
| Log to the lab DAQ | `rtl/infra/streaming_buffer.v` + `host/rp_optomech/stream.py` |
| Cross-axis (MIMO) coupling | `host/rp_optomech/feedback.py` `FeedbackController(K=...)` |

## To build it (the WP-7 path)
1. Generate the register interfaces: `python regspec/gen_all.py regspec/specs/nanosphere.yaml`. ✅ done
2. Lock-in measurement block + testbench (WP-5). ✅ done — `rtl/measurement/lock_in.v` passes `tb_lock_in`.
3. Write `fpga/create_block_design.tcl` (adapt the spin-controller's; or use WP-6's generator)
   to instantiate the generated regfile + 3 lock-in lanes + streaming. ⏳ needs Vivado.
4. Host: `host_demo.py` shows the config + monitor loop; supply a calibrated coupling matrix K
   for real MIMO cooling. ✅ skeleton done.

See [`../../docs/PORTING.md`](../../docs/PORTING.md) for the full checklist.
