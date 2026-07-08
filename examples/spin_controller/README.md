# Example: spin controller (the reference)

The optically-levitated-microsphere **spin controller** is the proven instrument this framework
was extracted from. It measures rotation frequency (Schmitt zero-crossing counter) and drives an
EOM to lock a spinning sphere at a setpoint. It is bench-verified over a DAC↔ADC loopback:
frequency exact to ~1% across 100 kHz–18 MHz, clean 1 MHz lock, verified two-board gate sync.

**The full, working implementation lives in its own repo:** `red-pitiya-spin-controller`
(Moore Lab). This directory is the *migration example* showing that a real, complex design maps
onto the framework.

## Migration status (PLAN WP-4) — ✅ DONE
- [x] [`regspec/specs/spin_controller.yaml`](../../regspec/specs/spin_controller.yaml) — the full
      42-register map (control + capture + dual freq counters + streaming + dual-axis PID/lock +
      multi-board sync), listed in map order with no explicit offsets.
- [x] [`verify_offsets.py`](verify_offsets.py) — the acceptance check. Asserts the allocator's
      offsets match the independently-transcribed `implementation_status.md` table. **PASSES: all
      42 registers, 0x00..0xA4, exact.** Run: `python examples/spin_controller/verify_offsets.py`.
- [ ] Host script using `BoardSession` + the generated `registers_spin_controller` module (thin;
      the source repo's `board_io.py` maps directly onto the generated names).

The generated `registers_spin_controller.py` is a drop-in for the source repo's hand-maintained
`REG_*` block; `spin_controller_regs.v` is a drop-in for the hand-written `axi_lite_slave.v` —
same map, generated from one source instead of hand-synced across three files.

## What it demonstrates once migrated
- The `channels:` construct reproduces the hand-copied axis-A / axis-B lanes.
- `freq_counter` is the reference measurement block behind the frozen interface.
- The generated register file is a drop-in for the hand-written `axi_lite_slave.v` — same map,
  no hand-sync.

Until the migration lands, treat the source repo as the authoritative spin-controller and this
directory as the tracking stub.
