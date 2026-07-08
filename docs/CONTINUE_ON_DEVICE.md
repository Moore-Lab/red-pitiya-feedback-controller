# Continuing on the device-connected machine

This repo was scaffolded and verified on a machine **without** the Red Pitaya or Vivado —
everything here is proven in simulation and unit tests, but nothing has touched real hardware
yet. This document is the handoff: what to install, how to confirm the baseline, and the
ordered next steps that need the board + Vivado (which only exist on the connected machine).

## 0. Get the repo + toolchain

```bash
git clone https://github.com/Moore-Lab/red-pitiya-feedback-controller.git
cd red-pitiya-feedback-controller
```

Install on the connected machine (the versions the reference spin controller uses):
- **Vivado ML 2025.2.1** with the Zynq-7000 device files (the spin-controller notes: only the
  install that has the Zynq-7010 part will work — check `get_parts xc7z010clg400-1`).
- **Icarus Verilog** (`iverilog`/`vvp`) for the simulations.
- **Python 3** with `pip install -r requirements.txt pytest` (host + codegen). The board's own
  Python is 3.5 and needs nothing installed — the generated register module + `daemon.py` are
  stdlib-only.
- SSH access to the board(s): master `rp-f05d37.local` / `192.168.8.220`,
  slave `rp-f07746.local` / `192.168.8.159` (from the spin-controller session log).

## 1. Confirm the baseline (no hardware needed)

```bash
scripts/check_all.sh
```
Expect: 3 specs in sync, 20 Python tests, 14 Icarus sims — all green. If this passes, the
register codegen, the RTL library, and the host package are intact on your machine.

## 2. What's already done (don't rebuild it)

- **Register codegen** (`regspec/`): one YAML spec → AXI4-Lite Verilog + host Python + docs.
- **RTL library** (`rtl/`), all sim-verified: CIC, FIR, NCO, PID, lock-acquisition, streaming
  buffer, **`sync_io` (DAISY/SATA trigger sync)**, and two measurement blocks —
  `freq_counter` (frequency) and `lock_in` (I/Q displacement, incl. multi-board slave mode).
- **Host package** (`host/rp_optomech/`): spec-driven `BoardSession`, `StreamReader`,
  `FeedbackController`; on-board `daemon.py`.
- **Board pinout**: `constraints/red_pitaya.xdc` — the full STEMlab 125-14 map including the
  DAISY (SATA) sync pair (`daisy_p/n_o`, `daisy_p/n_i`, `DIFF_HSTL_I_18`, T12/U12/P14/R14).
- Reference: the fully-working, hardware-verified instrument is the sibling repo
  `red-pitiya-spin-controller` (its `docs/` has the measured numbers + gotchas).

## 3. The remaining work (needs Vivado + the board)

These are the `docs/PLAN.md` packages that could not be verified without hardware.

### WP-6 — spec-driven block-design generator  *(the key unlock)*
Write `scripts/gen_block_design.py`: given a spec + a lane description (which measurement block,
how many channels), emit a `create_block_design.tcl` that instantiates the generated
`<name>_regs`, one control lane per channel (measurement → `pid_controller` → `nco_summer` →
`dac_sine` → `dac_interface`), the `streaming_buffer`, and the DAISY sync path.

**Start from the reference**: `red-pitiya-spin-controller/fpga/scripts/create_block_design.tcl`
is a known-good 542-line IPI script for the exact same modules — generalize it, don't start
blank. Wire the generated register ports by name: `<reg>_o` outputs drive the PL, `<reg>_i`
inputs return PL status (see `docs/INTERFACES.md` §2).

*Acceptance*: generated Tcl builds a bitstream for `core` (or spin) with WNS ≥ 0. Build with
`launch_runs -jobs 1` and gate on WNS (both are carried-forward gotchas, `rtl/README.md`).

### Multi-board SATA trigger sync — wiring checklist
The pieces all exist; WP-6 is what connects them. To bring up two-board sync:
- [x] `rtl/infra/sync_io.v` (IBUFDS/OBUFDS, 2-FF CDC, master/slave/retransmit) — sim-verified.
- [x] `constraints/red_pitaya.xdc` DAISY block (`daisy_*` ports, `set_false_path` on DAISY-IN).
- [x] `sync_control` register in `core.yaml` (master/slave/retransmit enables) — generated.
- [x] `sync_reset` / `sync_slave_mode` hooks on `freq_counter` **and** `lock_in`.
- [ ] Block-design wiring: `sync_control_o` bits → `sync_io` control inputs; local
      `measurement.gate_done` → `sync_io.master_pulse`; `sync_io.sync_reset` fans out to every
      measurement block's `sync_reset` and to `streaming_buffer.sync_reset`; four DAISY
      top-level ports. **(WP-6 output.)**
- [ ] Host orchestration: port `red-pitiya-spin-controller/scripts/multi_board_test.sh` +
      `software/check_gate_alignment.py` into `host/` for two-board gate-alignment testing.
- [ ] Hardware bring-up: SATA cable between the two boards' DAISY connectors; set `sync_control`
      = master on one, slave on the other; confirm records align by index (the spin-controller
      measured `sync_flag` set on 200/200 slave records, RMS gate skew < 0.5 counts).

Cabling + verified behaviour reference: `red-pitiya-spin-controller/docs/multi_board_progress_report.md`.

### WP-7 — first downstream build (e.g. nanosphere)
Once WP-6 works: `python regspec/gen_all.py regspec/specs/nanosphere.yaml`, build the block
design (3 lock-in lanes), load, and verify. Bring-up order (simulate first, then hardware):
1. Heartbeat LED + `magic` reads 0xDEADBEEF + `scratch` round-trips.
2. Drive a known tone into an ADC (or DAC→ADC loopback); confirm the lock-in magnitude
   (`meas_mag_<i>`) peaks when `lockin_ref_tw_<i>` matches the tone, ≈0 off-band (this mirrors
   `tb_lock_in`, now on silicon).
3. Configure per-axis reference frequencies + gains and run `examples/nanosphere/host_demo.py`.
4. Close the loop with a calibrated coupling matrix K in `FeedbackController`.

### Optional refinements
- `lock_in.v`: replace the alpha-max-beta-min magnitude with a CORDIC `sqrt(I²+Q²)`; add an
  I/Q low-pass (reuse `cic_decimator` + `comp_fir`) ahead of the gate accumulator for
  narrowband work.
- `streaming_buffer`: parameterize `words_per_record` for non-default record layouts.

## 4. Working rhythm
Edit a spec → `python regspec/gen_all.py <spec>` (commit the generated files) → simulate the
touched modules (`scripts/run_sims.sh`) → build (`-jobs 1`, WNS ≥ 0) → load → verify against a
known signal **before** closing any loop on real optics. CI runs `scripts/check_all.sh` on push.
