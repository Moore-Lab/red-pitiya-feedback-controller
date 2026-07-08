# STATUS — red-pitaya-optomech

Single source of truth for progress. Orchestrator writes this; workers report via their task
notes. States: `ready` · `claimed` · `in-progress` · `blocked` · `in-review` · `done`.

**As of:** 2026-07-08 (initial scaffold).

| WP | Title | State | Owner | Evidence |
|----|-------|-------|-------|----------|
| WP-0 | Register-spec codegen | **done (scaffold)** | — | `regspec/` runs; `core.yaml` → V/Py/MD; `--check` green; generated Python imports; Verilog reviewed |
| WP-1 | Generated-regfile self-checking testbench | ready | — | — |
| WP-2 | RTL library parameterization + tb port | ready | — | modules copied into `rtl/`; testbenches not yet ported |
| WP-3 | Host package integration test | **done** | — | `pytest host/rp_optomech/tests/` → 9 passed (fake daemon; BoardSession/StreamReader/FeedbackController) |
| WP-4 | Spin-controller migration example | **done** | — | `spin_controller.yaml` (42 regs) → generated; `verify_offsets.py` PASSES (0x00..0xA4 exact) |
| WP-5 | Lock-in measurement block | blocked (interface freeze) | — | `lock_in.v` stub in place |
| WP-6 | Spec-driven block-design generator | ready (larger) | — | — |
| WP-7 | Nanosphere example (downstream build) | blocked (WP-5, WP-6) | — | `examples/nanosphere/` spec skeleton |

## What exists right now (scaffold deliverable)

- **Working, verified register-spec codegen** (`regspec/`): YAML → AXI4-Lite Verilog + host
  Python + Markdown, idempotent, with a 2-channel worked template (`core.yaml`, 25 registers).
- **Seed RTL library** (`rtl/`): 15 proven modules from the spin-controller + a manifest + the
  frozen measurement interface + a `lock_in` stub.
- **Host package** (`host/rp_optomech/`): spec-driven `BoardSession`, `StreamReader`,
  `FeedbackController`, on-board `daemon.py` — all import and pass basic logic checks.
- **Design docs** (`docs/`): SCOPE, ARCHITECTURE, INTERFACES, DECISIONS, PLAN, this file,
  PORTING; plus `regspec/SCHEMA.md` and role prompts.

## Not yet done
Testbenches for the generated regfile and the ported RTL; the host mock/integration test; the
full spin-controller 42-register migration; the lock-in completion; the block-design generator;
any hardware bring-up. See PLAN for the ordered path.
