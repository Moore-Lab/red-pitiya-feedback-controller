# rtl/ — reusable Verilog library

Seeded verbatim from the bench-verified `red-pitiya-spin-controller`. Each module below is a
proven building block; the **Generalization** column says what (if anything) must change to
use it in a multi-channel framework design. Modules marked *reuse as-is* are experiment- and
channel-agnostic already.

Every module has (or needs) a testbench that passes in Icarus Verilog **before** it goes to
hardware — carry the testbenches over from the source repo's `fpga/tb/` as you promote each
module. Simulate first, always.

## Library manifest

| Module | Dir | Function | Generalization |
|--------|-----|----------|----------------|
| `adc_interface` | io | LTC2145 capture, offset-binary → two's-complement | reuse as-is |
| `dac_interface` | io | AD9767 dual-DAC bus driver (interleaved, ODDR clock) | reuse as-is |
| `adc_mux` | io | 14-bit 2:1 channel select | reuse as-is (widen select for >2 ch) |
| `sign_extend_14to16` | io | 14→16 sign-extension adapter (IPI signedness fix) | reuse as-is |
| `cic_decimator` | dsp | 4-stage Hogenauer CIC, parameterizable R | reuse as-is (per channel) |
| `comp_fir` | dsp | 16-tap symmetric FIR, inverse-CIC droop compensation | reuse as-is; regen coeffs if R changes |
| `dac_sine` | dsp | NCO: 32-bit phase accum + 4096×14 sine LUT + amplitude | reuse as-is (per channel) |
| `nco_summer` | dsp | actual_tw = base_tw + (pid_corr << shift), saturated | reuse as-is (per channel) |
| `pid_controller` | feedback | fixed-point P+I, anti-windup, 3-stage pipeline, Q4.12 | reuse as-is (per channel) |
| `lock_acquisition` | feedback | IDLE→RAMPING→LOCKED state machine (ramp then hand to PID) | reuse as-is (per channel) |
| `freq_counter` | measurement | **reference measurement**: Schmitt zero-crossing + amp peak | one *implementation* of the measurement seam |
| `streaming_buffer` | infra | 4-word circular record per gate, sync-flag aware | generalize `words_per_record` for other layouts |
| `sync_io` | infra | multi-board DAISY trigger sync (2-FF, master/slave/retransmit) | reuse as-is |
| `blinker` | infra | heartbeat LED (register-driven half-period) | reuse as-is |

## Coefficient ROMs

`dac_sine` needs `sine_lut.mem`; `comp_fir` needs `fir_coeffs.mem`. Regenerate them with the
copied generators (`dsp/gen_sine_lut.py`, `dsp/gen_fir_coeffs.py`) rather than committing the
large `.mem` files — re-run after changing CIC parameters (R, N).

## Carried-forward hardware conventions (do not relearn the hard way)

From the source project's `docs/implementation_status.md` §9 — these bit the original build and
are documented so they don't bite again:

- **Vivado IPI zero-extends across cell boundaries even for `signed` signals.** Match widths or
  insert a sign-extension adapter (`sign_extend_14to16`).
- **`parameter signed [..] X` synthesises wrong** when negated at runtime. Use an input port and
  register the negation inside the module — never a signed parameter for a runtime value.
- **Pipeline long register→arithmetic chains.** The PID setpoint→integrator path needed 2–3
  stages to close timing at 125 MHz; `pid_controller` already ships pipelined.
- Build with `launch_runs -jobs 1` (a Vivado `report_utilization` segfault workaround) and gate
  on WNS ≥ 0.

## What's not here yet

- `lock_in` — the quadrature-demod measurement block for displacement/COM experiments. The
  interface it must satisfy is in [`measurement/INTERFACE.md`](measurement/INTERFACE.md); a stub
  is provided. This is the first downstream build (e.g. nanosphere).
- A spec-driven **block-design generator** (today each example hand-writes `create_block_design.tcl`).
