# PORTING — standing up a new experiment

How to build a new Red Pitaya feedback experiment (e.g. nanosphere COM cooling) on this
framework. The goal: **edit only your experiment's files — never `regspec/` or `rtl/` core.**

## 1. Write your register spec
Copy [`regspec/specs/core.yaml`](../regspec/specs/core.yaml) to
`regspec/specs/<experiment>.yaml`. Keep the shared header (control, magic, scratch, gate,
threshold, streaming) and edit the `channels:` block: set `count` to your number of control
axes and adjust the per-channel registers (add your measurement block's config registers, e.g.
`lockin_ref_tw`).

## 2. Generate the register interfaces
```
python regspec/gen_all.py regspec/specs/<experiment>.yaml
```
Produces `regspec/generated/<experiment>_regs.v`, `host/rp_optomech/registers_<experiment>.py`,
and the docs table. Commit them. Re-run whenever the spec changes; CI runs `--check`.

## 3. Choose or write your measurement block
- Frequency lock? Use `rtl/measurement/freq_counter.v` as-is.
- Displacement / COM? Complete `rtl/measurement/lock_in.v` (see its TODOs and
  [`rtl/measurement/INTERFACE.md`](../rtl/measurement/INTERFACE.md)). Any block that satisfies
  the interface (`error_count`, `amplitude`, `gate_done`) drops straight into a lane.
Write its testbench and simulate against an injected tone **before** hardware.

## 4. Assemble the design
Under `examples/<experiment>/fpga/`, provide a top + a `create_block_design.tcl` that
instantiates: the generated `<experiment>_regs`, one control lane per channel
(measurement → `pid_controller` → `nco_summer` → `dac_sine` → `dac_interface`), the
`streaming_buffer`, and (if multi-board) `sync_io`. Wire the generated register ports by name
(`<reg>_o` outputs drive the PL, `<reg>_i` inputs return PL status). Until WP-6 lands, copy the
spin-controller's `create_block_design.tcl` and adapt it.

## 5. Write the host script
```python
from rp_optomech.board import BoardSession
from rp_optomech.feedback import Channel, FeedbackController
import registers_<experiment> as regs

with BoardSession("192.168.8.220", regs) as b:
    assert b.read("magic") == 0xDEADBEEF
    # configure lanes via b.write(...) / b.write_field(...), then run:
    chans = [Channel("x", b, "meas_count_ch0", "pid_setpoint_ch0", "lock_status_ch0"),
             Channel("y", b, "meas_count_ch1", "pid_setpoint_ch1", "lock_status_ch1")]
    FeedbackController(chans, K=my_coupling_matrix).run(targets, duration_s=10)
```
Add your physical unit conversions as the `meas_to_hz` / `hz_to_setpoint` callables on each
`Channel`.

## 6. Bring up
Simulate every module. Build with `-jobs 1`, gate on WNS ≥ 0. Load the bitstream, confirm the
heartbeat + `magic`, then verify the measurement block against a known injected signal before
closing the loop on real optics.

## Checklist
- [ ] spec written and generates cleanly (`gen_all.py`, `--check` green)
- [ ] measurement block simulated against an injected tone
- [ ] every RTL module in the design has a passing testbench
- [ ] block design builds with WNS ≥ 0
- [ ] heartbeat + `magic` + scratch round-trip on hardware
- [ ] measurement verified on a known signal before closing the loop
- [ ] **zero edits to `regspec/` or `rtl/` core** (if you needed one, it's a framework change — open a gate)
