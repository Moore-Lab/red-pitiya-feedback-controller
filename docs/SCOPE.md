# SCOPE — red-pitaya-optomech

## Objective

A reusable **starting-point framework** for Red Pitaya (Zynq-7010) real-time feedback
experiments in optomechanics: multi-channel signal acquisition → per-channel DSP →
measurement/error-signal extraction → PID/feedback law → multi-channel actuation, with every
parameter and readback exposed on a **runtime-configurable AXI register bank** and drained by
a host that runs multi-channel, multi-board feedback.

The framework is *extracted from* the proven `red-pitiya-spin-controller` (Moore Lab), which
becomes its reference example. A new experiment — e.g. nanosphere centre-of-mass (COM)
cooling — should stand up by writing a register spec, a measurement block, and a top-level
assembly, **without editing the framework core**.

## In scope

- **Register-spec codegen** (`regspec/`): one YAML source of truth → the AXI4-Lite Verilog
  register file + the host Python register module + the Markdown docs table. *The crown jewel;
  already working and verified.*
- **Reusable RTL library** (`rtl/`): I/O (ADC/DAC/mux), DSP (CIC, FIR, NCO), feedback (PID,
  lock-acquisition), infra (streaming buffer, multi-board sync, heartbeat), plus a **pluggable
  measurement interface** with a reference implementation (zero-crossing frequency counter)
  and a stub for the next one (lock-in / quadrature demod).
- **Channel parameterization**: the `channels:` spec construct replicates a control lane N
  times with auto-allocated register offsets (replaces the spin-controller's hand-copied
  axis-A/axis-B).
- **Host stack** (`host/rp_optomech/`): spec-driven `BoardSession` (name-addressed AXI over a
  persistent daemon), `StreamReader`, and an N-channel/multi-board `FeedbackController` with a
  coupling matrix.
- **Examples** (`examples/`): the spin-controller as the reference; a nanosphere skeleton.

## Out of scope (for the initial scaffold)

- Experiment-specific **physics and calibration** (torque models, mode frequencies, unit
  conversions) — these live in each experiment's example, not the core.
- A fully **auto-generated Vivado block design**. v1 keeps a hand-written `create_block_design.tcl`
  per example (as the spin-controller has); a spec-driven block-design generator is a planned
  work package, not a v1 promise.
- The actual **nanosphere firmware** and its lock-in DSP (scoped as the first downstream build,
  with a stub + interface provided here).
- Any **GUI**; host tooling is scripting-first.

## Success criteria (measurable)

1. `python regspec/gen_all.py <spec>` regenerates all three artifacts, and `--check` exits 0
   when they are in sync (CI-enforceable). ✅ *demonstrated for `core.yaml`.*
2. The spin-controller's full 42-register map is expressible in the schema and round-trips
   (a migration example under `examples/spin_controller/`).
3. A generated register file passes a self-checking AXI4-Lite testbench in Icarus/Vivado sim.
4. A new experiment reaches "heartbeat LED + AXI register read/write from the host" by editing
   only a spec + a top + a block-design — **zero edits to `regspec/` or `rtl/` core**.

## Key risks and how the design retires them

| Risk | Retirement |
|------|-----------|
| Register-map drift between Verilog / Python / docs (the #1 hazard in the source project) | Single-source-of-truth codegen + `--check` in CI. Already built. |
| Over-generalising before any physics validation | The spin-controller stays the proven reference; the framework is built *behind* it, not by rewriting it. Nothing ships to optics untested. |
| Channel-count explosion (hand-copying lanes) | The `channels:` construct; register offsets auto-allocate. Working. |
| Vivado IPI signedness surprises (zero-extension across cells; broken `parameter signed`) | Carried forward as documented conventions from the source project (see DECISIONS + rtl manifest). |
| Generated AXI slave subtly wrong | Frozen, versioned generator + a self-checking testbench as an acceptance gate (WP). |

## External dependencies

Vivado ML 2025.2.1 (with Zynq-7000 device files) · Icarus Verilog (sim) · Python 3 +
PyYAML + numpy (host/codegen; board-side is stdlib-only Python 3.5) · a Red Pitaya STEMlab
125-14 · Pavel Demin's `red-pitaya-notes` (pinout reference).

## Human gates

Scope sign-off (this doc) · **interface freeze** on the register-spec schema and the
measurement-block Verilog contract (see INTERFACES.md) · scope of the block-design generator ·
first hardware bring-up of a generated register file · any new experiment's optics bring-up.
