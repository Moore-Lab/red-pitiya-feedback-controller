# PLAN — red-pitaya-optomech

Work packages, dependencies, and executable acceptance checks. A package is sized to complete
in roughly one focused session. Status is tracked in [`STATUS.md`](STATUS.md).

## Work packages

### WP-0 — Register-spec codegen  ·  **DONE (scaffold)**
Build the spec loader/allocator and the three generators. **Owns** `regspec/`.
*Acceptance:* `python regspec/gen_all.py regspec/specs/core.yaml` writes all three artifacts;
`--check` exits 0; generated Python imports; generated Verilog matches the hand-written pattern.
✅ demonstrated.

### WP-1 — Generated-regfile self-checking testbench  ·  ready
Write `regspec/tb/tb_regfile.v` (or a cocotb test) that, for `core`, drives the AXI4-Lite
channel: writes each `rw` register and reads it back; reads each `ro/const`; drives `ro/input`
ports and reads them. **Owns** `regspec/tb/`.
*Acceptance:* `iverilog` sim over `generated/core_regs.v` prints PASS with full register
coverage. **Depends on** WP-0.

### WP-2 — RTL library parameterization + testbench port  ·  ready
Bring each `rtl/` module's testbench across from the source repo; confirm all pass under
Icarus. Parameterize `streaming_buffer` `words_per_record`; widen `adc_mux` select. **Owns**
`rtl/` (except `measurement/INTERFACE.md`).
*Acceptance:* every module in `rtl/` has a passing testbench; `make sim` (or a runner script)
is green.

### WP-3 — Host package integration test  ·  ready
Add a loopback/mock test for `host/rp_optomech`: a fake daemon socket that serves a register
model, exercised by `BoardSession` name access, `StreamReader`, and a 2-channel
`FeedbackController` with K≠0. **Owns** `host/rp_optomech/tests/`.
*Acceptance:* `pytest host/` passes with no hardware. **Depends on** WP-0 (registers module).

### WP-4 — Spin-controller migration example  ·  ready
Express the source project's full 42-register map as `regspec/specs/spin_controller.yaml`;
generate and diff the register offsets against the source `implementation_status.md` table.
Provide `examples/spin_controller/` (spec + host script + README) as the reference.
*Acceptance:* generated offsets match the source design's register table exactly. **Depends on**
WP-0.

### WP-5 — Lock-in measurement block  ·  blocked on interface freeze
Complete `rtl/measurement/lock_in.v` (NCO reference, I/Q LPF, CORDIC magnitude) + testbench
against an injected tone. **Owns** `rtl/measurement/lock_in.v`, `rtl/measurement/tb_lock_in.v`.
*Acceptance:* testbench recovers the amplitude/phase of a known injected quadrature signal
within tolerance. **Depends on** WP-2 and the frozen measurement interface.

### WP-6 — Spec-driven block-design generator  ·  ready (larger)
Generate `create_block_design.tcl` from a spec + a lane description (which measurement block,
how many channels), instantiating the generated regfile + the lane modules + BRAM controllers.
**Owns** `scripts/gen_block_design.py`.
*Acceptance:* generated Tcl builds a bitstream for `core`/spin in Vivado with WNS ≥ 0.

### WP-7 — Nanosphere example (first real downstream build)  ·  blocked
`examples/nanosphere/`: a spec (3 channels x/y/z, lock-in measurement), a top, host scripts.
*Acceptance:* heartbeat + AXI R/W from host on hardware, then lock-in reads a known injected
tone — **with zero edits to `regspec/` or `rtl/` core** (the success criterion from SCOPE).
**Depends on** WP-5, WP-6.

## Dependency DAG

```
WP-0 ─┬─ WP-1 (regfile tb)
      ├─ WP-3 (host tests)
      ├─ WP-4 (spin migration)
      └─ WP-2 (rtl tb port) ── WP-5 (lock_in) ─┐
                              WP-6 (bd gen) ────┴─ WP-7 (nanosphere)
```

**Parallel batch after WP-0:** WP-1, WP-2, WP-3, WP-4 (no shared paths — different owners).
WP-5 and WP-6 can then run in parallel; WP-7 serializes last.

## Gates
Interface freeze (register-spec schema + measurement interface) before WP-5/WP-7 · block-design
generator scope (WP-6) · first hardware bring-up of a generated regfile · nanosphere optics.
