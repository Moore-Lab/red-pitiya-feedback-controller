# DECISIONS — red-pitaya-optomech

Append-only ADR log. Each entry: decision · context · alternatives · rationale · date.

---

### ADR-001 — Extract a framework rather than fork per experiment (2026-07-08)
**Decision.** Build a reusable Red Pitaya feedback framework and treat the spin controller as
its reference example, instead of copy-forking the spin-controller repo for each new experiment.
**Context.** The spin-controller is a bench-verified multi-channel feedback instrument; a
nanosphere COM experiment needs the same skeleton (register bank, DSP, PID, streaming, host,
multi-board) with a different measurement block.
**Alternatives.** (a) Fork-and-edit per experiment — diverges immediately, fixes don't
propagate. (b) One monorepo of experiments — heavier coupling.
**Rationale.** The reusable core is large and the experiment-specific part is small (one
measurement block + calibration). A framework maximises reuse and keeps the proven instrument
untouched.

### ADR-002 — New separate repo, not an in-place restructure (2026-07-08)
**Decision.** The framework lives in its own repo (`red-pitaya-optomech`); the spin-controller
repo is unchanged except for a pointer.
**Rationale.** Cleanest boundary; does not risk the working, bench-verified firmware. Chosen by
the user at the scope gate. (Alternative considered: split the existing repo into `core/` +
`experiments/` — rejected to avoid touching proven code.)

### ADR-003 — Register map is a single source of truth with codegen (2026-07-08)
**Decision.** One YAML register spec generates the Verilog register file, the host Python
module, and the docs table. Generated files are committed and CI-checked (`gen_all.py --check`).
**Context.** In the source project the map was hand-maintained in three places
(`axi_lite_slave.v`, `board_io.py`, the docs) with a "keep in sync" comment — the #1 drift
hazard.
**Alternatives.** IP-XACT / SystemRDL (heavier, tooling-oriented); keep hand-syncing (status
quo, rejected).
**Rationale.** A small purpose-built YAML + generator is enough, hackable, and directly serves
the "runtime-configurable register" goal. **This is the crown jewel and is built + verified.**

### ADR-004 — YAML for specs; generated Python is stdlib-only (2026-07-08)
**Decision.** Specs are YAML (PyYAML on the dev machine). The generated `registers_<name>.py`
imports nothing (plain constants + a dict) so it runs on the board's Python 3.5.
**Rationale.** YAML is pleasant to hand-edit; the board must stay dependency-free. Generation
happens on the dev host, not the board.

### ADR-005 — Pluggable measurement block behind a fixed interface (2026-07-08)
**Decision.** Define a frozen measurement-block Verilog interface (`error_count`, `amplitude`,
`gate_done`). `freq_counter` is the reference impl; `lock_in` is the seam for displacement
experiments.
**Rationale.** Isolates the one experiment-specific RTL module so PID/lock/streaming/registers
are reused verbatim.

### ADR-006 — Channel replication is a spec construct (2026-07-08)
**Decision.** A `channels:` block stamps a lane template out N times with auto-allocated
offsets, replacing the source project's hand-copied axis-A/axis-B and manual offset counting.
**Rationale.** Scaling to spin + x/y/z COM (the source project's own "reg42–reg54, six axes"
note) must not be manual.

### ADR-007 — Block-design auto-generation deferred (2026-07-08)
**Decision.** v1 keeps a hand-written `create_block_design.tcl` per example; a spec-driven
generator is a later work package (see PLAN WP-6).
**Rationale.** Right-size the scaffold. The register-file codegen retires the highest-value
drift risk now; auto-wiring the whole IPI design is a larger effort best done once the RTL
library's parameterization has settled.

### ADR-008 — Carry forward the source project's hardware conventions (2026-07-08)
**Decision.** Adopt verbatim the IPI-signedness, signed-parameter, pipelining, and
`-jobs 1`/WNS-gate conventions documented in the spin-controller.
**Rationale.** These were learned the hard way on real silicon; re-deriving them would waste
build cycles. Recorded in `rtl/README.md`.
