# Measurement-block interface (frozen contract)

The measurement block is the one experiment-specific RTL module in a control lane. It turns a
per-channel ADC stream into an **error signal** that the shared `pid_controller` acts on. Fix
this interface and the entire datapath — PID, lock acquisition, streaming, register bank — is
reused unchanged across experiments.

## Required ports

```verilog
module <measurement> #(
    parameter integer DATA_WIDTH = 16
)(
    input  wire                     clk,          // 125 MHz fabric clock
    input  wire                     rst_n,
    input  wire signed [DATA_WIDTH-1:0] adc_sample,  // this channel's sign-extended ADC input

    // shared configuration (driven by generated register outputs)
    input  wire        [31:0]       gate_cycles,  // measurement window length in clk cycles
    input  wire        [15:0]       threshold,    // discriminator half-band / sensitivity (codes)

    // --- block-specific config may be added here (e.g. lock-in reference NCO word) ---

    // outputs consumed by the shared lane
    output wire signed [31:0]       error_count,  // the error signal (freq count, displacement, ...)
    output wire        [15:0]       amplitude,    // measured amplitude over the gate
    output wire                     gate_done     // 1-cycle strobe at the end of each gate window
);
```

## Semantics

- **`gate_done`** is the heartbeat of the lane: it clocks the `pid_controller` update, the
  `lock_acquisition` step, and the `streaming_buffer` write. Emit exactly one cycle per gate.
- **`error_count`** is whatever the PID should drive to a setpoint. For a frequency-lock
  experiment it is a cycle count (∝ frequency); for a displacement experiment it is a demodulated
  quadrature magnitude or a phase. It is compared against `pid_setpoint` (a register) as a signed
  quantity.
- **`amplitude`** is logged/streamed and used for signal-present / SNR checks; it does not enter
  the control law directly.
- In multi-board designs, the block also accepts `sync_reset` / `sync_slave_mode` (see
  `infra/sync_io.v` and the source project's `freq_counter.v`) so a master board's gate governs
  the slaves. Optional for single-board designs.

## Reference implementations

| Block | Error signal | Use |
|-------|--------------|-----|
| `freq_counter.v` (present, tested) | Schmitt zero-crossing count over the gate → rotation frequency | spin controller |
| `lock_in.v` (present, tested) | I/Q mix ADC × internal reference NCO, gate-accumulate → magnitude (block-specific config: `ref_tuning_word`) | nanosphere COM |

A compliant block is a drop-in: instantiate it in the lane in place of the reference, wire its
block-specific config to spec registers, and the rest of the design is unchanged.
