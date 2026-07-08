# red-pitaya-optomech

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
regspec/   register spec + code generators (spec -> Verilog + Python + docs)
rtl/       reusable Verilog library: io/ dsp/ feedback/ measurement/ infra/
host/      rp_optomech: spec-driven BoardSession, StreamReader, FeedbackController, daemon
examples/  spin_controller/ (reference) · nanosphere/ (skeleton)
docs/      SCOPE · ARCHITECTURE · INTERFACES · PLAN · STATUS · DECISIONS · PORTING
roles/     orchestrator + worker execution-protocol prompts
```

## Requirements
Vivado ML 2025.2.1 (Zynq-7000 device files) · Icarus Verilog (sim) · Python 3 + PyYAML + numpy
(host/codegen; the board daemon and generated register module are stdlib-only Python 3.5) · a
Red Pitaya STEMlab 125-14.

## Status
Initial scaffold. **Working & verified:** the register-spec codegen. **Seeded:** the RTL library
(15 proven modules) and the host package. **Next:** testbenches for the generated regfile and
ported RTL, the spin-controller migration, the lock-in block, and the block-design generator —
see [`docs/PLAN.md`](docs/PLAN.md).
