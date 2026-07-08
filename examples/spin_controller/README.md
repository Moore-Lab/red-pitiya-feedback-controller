# Example: spin controller (the reference)

The optically-levitated-microsphere **spin controller** is the proven instrument this framework
was extracted from. It measures rotation frequency (Schmitt zero-crossing counter) and drives an
EOM to lock a spinning sphere at a setpoint. It is bench-verified over a DAC↔ADC loopback:
frequency exact to ~1% across 100 kHz–18 MHz, clean 1 MHz lock, verified two-board gate sync.

**The full, working implementation lives in its own repo:** `red-pitiya-spin-controller`
(Moore Lab). This directory is the *migration example* showing that a real, complex design maps
onto the framework.

## Migration status (PLAN WP-4)
- [ ] `regspec/specs/spin_controller.yaml` — express the full 42-register map (control + capture
      + dual freq counters + streaming + dual-axis PID/lock + multi-board sync) in the spec schema.
- [ ] Generate and diff the register offsets against the source repo's
      `docs/implementation_status.md` table — they must match exactly (the acceptance check).
- [ ] Host script using `BoardSession` + the generated `registers_spin_controller` module.

## What it demonstrates once migrated
- The `channels:` construct reproduces the hand-copied axis-A / axis-B lanes.
- `freq_counter` is the reference measurement block behind the frozen interface.
- The generated register file is a drop-in for the hand-written `axi_lite_slave.v` — same map,
  no hand-sync.

Until the migration lands, treat the source repo as the authoritative spin-controller and this
directory as the tracking stub.
