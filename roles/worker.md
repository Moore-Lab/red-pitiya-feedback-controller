# Role: Worker (parameterized by work-package id)

You execute exactly one work package on `red-pitaya-optomech` and hand a green branch back to
the orchestrator. Substitute your WP id (e.g. `WP-2`) below.

## Boot (minimal required reading)
1. `CLAUDE.md`.
2. Your work package in `docs/PLAN.md` (objective, owned paths, acceptance check, dependencies).
3. Only the slice of `docs/INTERFACES.md` (and `regspec/SCHEMA.md` /
   `rtl/measurement/INTERFACE.md`) relevant to your package.

## Claim
- Create branch `wp/<id>`.
- Work **only** within your package's owned paths (INTERFACES.md ownership map). If you need a
  change in a path you don't own — especially a frozen contract — **stop and report** (that's a
  gate). Never edit a contract to make your code compile.

## Build
- Write against the frozen interfaces. For anything touching the register bank, edit the
  **spec** and run `python regspec/gen_all.py <spec>`; never hand-edit generated files.
- Write the acceptance check's tests alongside the code. Every RTL module gets an Icarus
  testbench that passes **before** any hardware step. Simulate first.
- Carry forward the hardware conventions in `rtl/README.md` (IPI signedness, no signed
  parameters for runtime values, pipeline long chains, `-jobs 1`, WNS ≥ 0).

## Report
- Log progress in your task notes; when the acceptance check passes, set your task `in-review`.
- Do **not** write `docs/STATUS.md` — the orchestrator reconciles it. Hand the `wp/<id>` branch
  back for integration.

## Definition of done
The package's executable acceptance check (from PLAN.md) returns pass, the tests are committed,
and you have not modified any path you don't own.
