# STATUS — red-pitaya-optomech

Single source of truth for progress. Orchestrator writes this; workers report via their task
notes. States: `ready` · `claimed` · `in-progress` · `blocked` · `in-review` · `done`.

**As of:** 2026-07-08 (scaffold + WP-1/2/3/4 verified). One-command verification:
`scripts/check_all.sh` (codegen sync-check on all specs + host pytest + 13 sims) — **all green.**

| WP | Title | State | Owner | Evidence |
|----|-------|-------|-------|----------|
| WP-0 | Register-spec codegen | **done** | — | `regspec/` runs; `core.yaml` → V/Py/MD; `--check` green; 11 unit tests (`regspec/tests/`) cover allocation/channels/validation; generated Verilog verified by `tb_regfile` |
| WP-1 | Generated-regfile self-checking testbench | **done** | — | `regspec/tb/tb_regfile.v` PASSES in Icarus (reset/const/rw/wstrb/input/ro-protect) |
| WP-2 | RTL library parameterization + tb port | **done** | — | 12 module tbs pass via `scripts/run_sims.sh` (13/13 with tb_regfile). Untested by design: pure pin-driver bus modules `adc_interface`/`dac_interface`. `streaming_buffer` words_per_record param = follow-up. |
| WP-3 | Host package integration test | **done** | — | `pytest host/rp_optomech/tests/` → 9 passed (fake daemon; BoardSession/StreamReader/FeedbackController) |
| WP-4 | Spin-controller migration example | **done** | — | `spin_controller.yaml` (42 regs) → generated; `verify_offsets.py` PASSES (0x00..0xA4 exact) |
| WP-5 | Lock-in measurement block | **done (core)** | — | I/Q demod + gate accumulate + magnitude; `tb_lock_in` PASS (in-band 2.1M vs off-band 16 vs DC 0). CORDIC magnitude = refinement. |
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

## Done since scaffold (all verified locally)
- **WP-1** generated-regfile testbench (`tb_regfile` PASS).
- **WP-2** RTL library testbenches (12 modules, `run_sims.sh` 13/13).
- **WP-3** host integration tests (`pytest` 9/9, fake daemon).
- **WP-4** spin-controller migration (42 regs reproduced exactly, `verify_offsets.py` PASS).
- **WP-5 (core)** I/Q lock-in demodulator, `tb_lock_in` PASS (~130,000x out-of-band rejection).
- **Multi-board SATA/DAISY sync — spec-complete:** `constraints/red_pitaya.xdc` (DAISY pins),
  `sync_control` register in `core.yaml`, and `sync_reset`/`sync_slave_mode` hooks on both
  measurement blocks (`tb_lock_in` slave-mode case PASS). Block-design wiring is the remaining
  step (WP-6) — see `docs/CONTINUE_ON_DEVICE.md`.
- **Lane integration (composition) sims:** `tb_lane_datapath` (nco_summer→dac_sine→sign_extend→
  freq_counter gives exact commanded counts) and `tb_lane_closed_loop` (lock_acquisition + PID +
  the datapath acquire and hold a setpoint). Proves the reusable modules compose — de-risks the
  block-design wiring (WP-6) and hardware bring-up.
- `scripts/check_all.sh` + `.github/workflows/ci.yml` — one-command / CI verification (16 sims).

## Not yet done
The spec-driven block-design generator (WP-6); the nanosphere downstream build (WP-7); a CORDIC
sqrt magnitude + I/Q low-pass for the lock-in (refinement); `streaming_buffer` record-width
parameterization; and any hardware bring-up (needs a board + Vivado). See PLAN for the path.
