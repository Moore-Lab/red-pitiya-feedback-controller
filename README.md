# red-pitiya-feedback-controller

> GitHub: **Moore-Lab/red-pitiya-feedback-controller** · Python package: `rp_optomech`

A reusable **starting-point framework** for building real-time feedback controllers on a Red
Pitaya (Xilinx Zynq-7010) for optomechanics experiments — levitated microspheres, nanospheres,
and similar. It gives you the parts every such experiment shares:

- **many input channels** (photodiodes, homodyne, PSS) → per-channel DSP → a measurement;
- **feedback loops** (PID + lock acquisition) driving **many output channels** (EOM, AOM, piezo);
- everything exposed on a **runtime-configurable AXI register bank**, with data streamed to a
  host that runs **multi-channel, multi-board feedback** with a coupling matrix.

It is extracted from the bench-verified **spin controller** (`red-pitiya-spin-controller`, Moore
Lab, Yale), which is its reference example. A new experiment stands up by writing a register spec
and a measurement block — **without editing the framework core**.

## The idea in one picture

```
 ADC channels → per-channel DSP → measurement block → PID + lock → NCO/DAC → actuator
      │              (CIC/FIR)     (freq counter │       (feedback)              │
      │                            lock-in / …)  │                              │
      └──────────── runtime-configurable AXI register bank ──────────────┬──────┘
                    (setpoints · gains · enables · readbacks · stream)    │
                         host: BoardSession · StreamReader · FeedbackController(K)
```

The only experiment-specific RTL is the **measurement block**. Swap `freq_counter` (rotation
frequency) for a `lock_in` (displacement) and the same PID / lock / streaming / register / host
stack re-targets to a different experiment.

## Start here
| If you want to… | Read |
|-----------------|------|
| Understand the design and what's reusable | [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) |
| See the scope, success criteria, and gates | [`docs/SCOPE.md`](docs/SCOPE.md) |
| See the frozen contracts (schema, measurement interface, host API) | [`docs/INTERFACES.md`](docs/INTERFACES.md) |
| Stand up a new experiment | [`docs/PORTING.md`](docs/PORTING.md) |
| **Continue development on the Red-Pitaya-connected machine** (Vivado + board) | [`docs/CONTINUE_ON_DEVICE.md`](docs/CONTINUE_ON_DEVICE.md) |
| See the plan and current status | [`docs/PLAN.md`](docs/PLAN.md) · [`docs/STATUS.md`](docs/STATUS.md) |

## The register system (the core piece, working today)
One YAML spec is the single source of truth for a design's register bank; it generates the
Verilog register file, the host Python module, and the docs — so they can never drift.

```
python regspec/gen_all.py regspec/specs/core.yaml
#   -> regspec/generated/core_regs.v            (AXI4-Lite slave register file)
#   -> host/rp_optomech/registers_core.py       (host register module)
#   -> regspec/generated/core_registers.md      (docs table)
python regspec/gen_all.py regspec/specs/core.yaml --check   # CI: fail if out of sync
```

`regspec/specs/core.yaml` is the template a new design copies. It shows shared registers plus a
`channels:` block that replicates a control lane N times (spin + x/y/z COM …) with
auto-allocated offsets.

## Layout
```
regspec/     register spec + code generators (spec -> Verilog + Python + docs)
rtl/         reusable Verilog library: io/ dsp/ feedback/ measurement/ infra/
host/        rp_optomech: spec-driven BoardSession, StreamReader, FeedbackController, daemon
constraints/ red_pitaya.xdc — STEMlab 125-14 board pinout incl. the DAISY (SATA) sync pair
examples/    spin_controller/ (reference) · nanosphere/ (skeleton)
docs/        SCOPE · ARCHITECTURE · INTERFACES · PLAN · STATUS · DECISIONS · PORTING · CONTINUE_ON_DEVICE
roles/       orchestrator + worker execution-protocol prompts
```

## Requirements
Vivado ML 2025.2.1 (Zynq-7000 device files) · Icarus Verilog (sim) · Python 3 + PyYAML + numpy
(host/codegen; the board daemon and generated register module are stdlib-only Python 3.5) · a
Red Pitaya STEMlab 125-14.

## Verify everything
```
scripts/check_all.sh    # codegen sync-check (all specs) + host pytest + 13 Icarus sims
```
Needs `python` (+ PyYAML, numpy, pytest) and `iverilog`/`vvp`. Also runs in CI
([`.github/workflows/ci.yml`](.github/workflows/ci.yml)).

## Status
**Verified (WP-0..4):** the register-spec codegen; a self-checking AXI4-Lite testbench for the
generated register file; 12 ported RTL-library testbenches (13/13 sims green); the host package
integration tests (9/9); and the **full spin-controller 42-register map reproduced exactly**
(`examples/spin_controller/verify_offsets.py`). **Next:** the lock-in measurement block, the
spec-driven block-design generator, and the nanosphere downstream build — see
[`docs/PLAN.md`](docs/PLAN.md) / [`docs/STATUS.md`](docs/STATUS.md).
