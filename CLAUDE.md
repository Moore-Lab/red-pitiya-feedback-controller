# CLAUDE.md — red-pitiya-feedback-controller

**Repo:** Moore-Lab/red-pitiya-feedback-controller (Python package `rp_optomech`).

**What / why.** A reusable starting-point framework for Red Pitaya (Zynq-7010) real-time
feedback experiments in optomechanics: multi-channel acquisition → per-channel DSP →
measurement → PID/feedback → multi-channel actuation, all exposed on a **runtime-configurable
AXI register bank** and driven by a multi-channel/multi-board host. Extracted from the proven
`red-pitiya-spin-controller`; a new experiment (e.g. nanosphere COM) stands up by writing a
register spec + a measurement block + a top, **without editing the framework core**.

**Continuing on the machine wired to the Red Pitaya (Vivado + board):** start from
[`docs/CONTINUE_ON_DEVICE.md`](docs/CONTINUE_ON_DEVICE.md). Everything here is verified in
simulation/tests only — no hardware has been touched yet.

## Read these to orient (in order)
1. [`README.md`](README.md) — the hub.
2. [`docs/SCOPE.md`](docs/SCOPE.md) — objective, boundaries, success criteria, gates.
3. [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — the generic model, module map, the channel
   lane, the measurement seam.
4. [`docs/INTERFACES.md`](docs/INTERFACES.md) — **frozen contracts** + path-ownership map.
5. [`docs/PLAN.md`](docs/PLAN.md) + [`docs/STATUS.md`](docs/STATUS.md) — work packages + ledger.
6. [`docs/PORTING.md`](docs/PORTING.md) — how to stand up a new experiment.

## The crown jewel
`regspec/` is a **single source of truth** register system: one YAML spec generates the AXI4-Lite
Verilog register file, the host Python module, and the docs table. This replaces the source
project's hand-synced three-way register map. Run it:
```
python regspec/gen_all.py regspec/specs/core.yaml            # generate V + Py + MD
python regspec/gen_all.py regspec/specs/core.yaml --check     # CI: fail if out of sync
python regspec/regspec.py regspec/specs/core.yaml             # print the resolved map
```
**Never hand-edit `regspec/generated/` or `host/rp_optomech/registers_*.py`** — edit the spec
and regenerate.

## Directory map
- `regspec/` — spec loader + generators + specs + generated outputs (the register system).
- `rtl/` — reusable Verilog library (`io/ dsp/ feedback/ measurement/ infra/`), seeded from the
  spin-controller; see `rtl/README.md` for the manifest and what needs parameterizing.
- `host/rp_optomech/` — spec-driven host package (`board`, `stream`, `feedback`, `daemon`).
- `examples/` — `spin_controller/` (reference), `nanosphere/` (skeleton).
- `docs/`, `roles/` — the workspace + execution protocol.

## Verify everything
```
scripts/check_all.sh   # codegen sync-check (all specs) + host pytest + 13 Icarus sims
scripts/run_sims.sh    # just the RTL + regfile testbenches
python -m pytest host/rp_optomech/tests/   # just the host package
```
Needs `python` (PyYAML, numpy, pytest) + `iverilog`/`vvp` on PATH. CI: `.github/workflows/ci.yml`.

## Conventions
- **Spec before code; simulate before hardware.** Every RTL module gets an Icarus testbench that
  passes before any bitstream. Build with `-jobs 1`, gate on WNS ≥ 0.
- **One writer per fact**; frozen contracts change only via a gate (see INTERFACES.md).
- Carry forward the hardware gotchas in `rtl/README.md` (Vivado IPI signedness, no signed
  parameters for runtime values, pipeline long chains).
- Host/codegen run on Python 3 (PyYAML + numpy). The board daemon and generated register module
  are stdlib-only Python 3.5.

## Provenance
The proven instrument and its verified performance numbers live in the sibling repo
`red-pitiya-spin-controller` (`docs/implementation_status.md`). This framework makes that
reusable; it does not reinvent it.
