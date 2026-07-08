# ARCHITECTURE — red-pitaya-optomech

## The generic model

Every experiment this framework targets is the same shape, stripped of its physics:

```
 N ADC channels        per-channel DSP         measurement            feedback law        M DAC channels
 (PSS, PD, homodyne) → (decimate / filter / → (error signal:     →   (PID + lock /    →  (EOM, AOM,
                        demodulate)            freq, phase, disp.)     state-space)        piezo, coils)
        ▲                                            │                      │                   │
        │                                            ▼                      ▼                   ▼
        │                                   ┌───────────────────── AXI register bank ──────────────────┐
        │                                   │  setpoints · gains · enables · readbacks · streamed data  │
        └───────────────────────────────────┴──────────────────────────┬───────────────────────────────┘
                                                                        │ AXI-lite + streaming BRAM
                                                    host: BoardSession · StreamReader · FeedbackController(K)
                                                          (multi-channel, multi-board, coupling matrix)
```

The only piece that changes between a **spin controller** (measure rotation frequency, actuate
an EOM) and a **nanosphere COM controller** (measure displacement by lock-in, actuate a
feedback force) is the **measurement block** and the physical calibration. Everything else —
register bank, DSP, PID, lock, streaming, host, multi-board — is shared.

## Module map

```
regspec/                 register-spec single source of truth + codegen  ── the crown jewel
  regspec.py             load/validate/allocate a YAML spec
  generators/            spec -> Verilog regfile | Python module | Markdown docs
  specs/*.yaml           per-design register maps (core.yaml = template)
  generated/*_regs.v     GENERATED AXI4-Lite slave (do not edit)

rtl/                     reusable Verilog library (seeded from the spin-controller)
  io/                    adc_interface, dac_interface, adc_mux, sign_extend_14to16
  dsp/                   cic_decimator, comp_fir, dac_sine (NCO), nco_summer (+ coeff gens)
  feedback/              pid_controller (anti-windup, pipelined), lock_acquisition (ramp->hold)
  measurement/           the pluggable seam: INTERFACE.md + freq_counter (reference) + lock_in (stub)
  infra/                 streaming_buffer, sync_io (multi-board DAISY), blinker (heartbeat)

host/rp_optomech/        spec-driven host package
  board.py               BoardSession: name-addressed AXI + BRAM over a persistent daemon
  daemon.py              on-board TCP AXI bridge (Python 3.5, /dev/mem)
  stream.py              StreamReader: drain the streaming ring buffer
  feedback.py            FeedbackController: N-channel/multi-board loop with coupling matrix K

examples/                one directory per experiment (spec + top + block-design + host script)
  spin_controller/       the proven reference (migration of the existing 42-register design)
  nanosphere/            skeleton for COM cooling (lock-in measurement, N=3 for x/y/z)
```

## The channel lane

A **control lane** is the repeating unit of a multi-channel design:

```
adc[k] → measurement_block → error → pid_controller → nco_summer → dac_sine → dac[k]
                               ▲                          ▲
                          setpoint (reg)          lock_acquisition (reg: target, ramp)
```

Its per-channel registers (nco_tuning_word, nco_amplitude, pid_setpoint, pid_gains,
pid_output, lock_status, meas_count, meas_amp, …) are declared **once** in the spec's
`channels:` block and replicated N times with auto-allocated offsets. In the source project
this replication was done by hand (axis A = `_0`, axis B = `_1`, offsets counted manually);
here it is a spec construct.

## The measurement seam

The measurement block is the one experiment-specific RTL module. It satisfies a fixed
interface (see [INTERFACES.md](INTERFACES.md) and
[`rtl/measurement/INTERFACE.md`](../rtl/measurement/INTERFACE.md)):

```
measurement( clk, rst_n, adc_sample, cfg_regs... ) -> ( error_count, amplitude, gate_done )
```

- **`freq_counter`** (reference) satisfies it by Schmitt zero-crossing counting → rotation
  frequency. Used by the spin controller.
- **`lock_in`** (stub) will satisfy it by I/Q mixing the ADC against the channel NCO and
  low-pass filtering → displacement amplitude & phase. Intended for nanosphere COM.

Because the interface is fixed, swapping the measurement block re-targets the whole datapath
without touching PID, lock, streaming, or the register bank.

## Data flow to the host

The `streaming_buffer` writes one fixed record per measurement gate into a circular BRAM the
PS exposes. `StreamReader` drains it (via the daemon's block-read) into numpy structured
arrays for HDF5 logging alongside the lab's other channels — matching the source project's
"the DAQ polls the Red Pitaya into the same HDF5" model. Latched single registers
(`meas_count`, `lock_status`, …) give a low-latency alternative for the control loop.

## Multi-board scaling

`sync_io` distributes a gate/trigger over the Red Pitaya DAISY connector (2-FF synchroniser,
master/slave/retransmit), so channel count scales past one board's 2 ADC / 2 DAC. The host
`FeedbackController` already spans multiple `BoardSession`s and applies a coupling matrix K
across all their channels.

## Provenance

Every RTL module and host pattern here is lifted from `red-pitiya-spin-controller`, where it
was bench-verified over a DAC↔ADC loopback (frequency exact to ~1% across 100 kHz–18 MHz,
clean 1 MHz lock, verified two-board gate sync). This framework's job is to make that reusable,
not to reinvent it. See that repo's `docs/implementation_status.md` for the verified numbers.
