# INTERFACES — red-pitaya-optomech (frozen contracts)

These are the contracts that let the register bank, the RTL, and the host be developed
independently. **Changing one is a gate, not a unilateral edit** (see SCOPE gates). Each fact
lives here once; other files link to it.

---

## 1. Register-spec schema

The authoritative schema is [`regspec/SCHEMA.md`](../regspec/SCHEMA.md), with the worked
template at [`regspec/specs/core.yaml`](../regspec/specs/core.yaml). Summary of the contract:

- A spec has `meta` (name, base_address, data_width), a `registers:` list of shared
  registers, and an optional `channels:` block replicated `count` times.
- Register: `name`, `access` (`rw` | `ro`), optional `offset` (auto-allocated if omitted),
  `reset`, `source` (`input` | `const`, for `ro`), optional `fields` (bitfields).
- Offsets are byte offsets from `base_address`, aligned to `data_width/8`; auto-allocation
  packs into the lowest free aligned word in list order.

## 2. Generated register-file module (RTL boundary)

`regspec/gen_all.py` emits `<name>_regs` with **fixed port-naming conventions** — the RTL that
instantiates it depends on these:

| Spec register | Generated port | Direction | Meaning |
|---------------|----------------|-----------|---------|
| `access: rw` | `<name>_o [DW-1:0]` | module **output** | current stored value, drives the PL |
| `access: ro, source: input` | `<name>_i [DW-1:0]` | module **input** | PL drives it; PS reads it back |
| `access: ro, source: const` | *(no port)* | — | read returns the `reset` constant |

Plus the standard AXI4-Lite slave channel (`S_AXI_*`) on `S_AXI_ACLK` / `S_AXI_ARESETN`.
Parameters: `ADDR_WIDTH` (from the spec's span), `DATA_WIDTH`. **Do not edit the generated
file**; change the spec and regenerate.

## 3. Measurement-block interface (the pluggable seam)

Full contract in [`rtl/measurement/INTERFACE.md`](../rtl/measurement/INTERFACE.md). Any
measurement block MUST present:

```verilog
module <meas> (
    input  wire               clk,        // 125 MHz fabric clock
    input  wire               rst_n,
    input  wire signed [15:0] adc_sample, // sign-extended ADC input for this channel
    input  wire        [31:0] gate_cycles,// measurement window (shared reg)
    input  wire        [15:0] threshold,  // discriminator half-band (shared reg)
    // ... block-specific config inputs (e.g. lock-in NCO word) ...
    output wire signed [31:0] error_count,// the error signal (e.g. freq count / displacement)
    output wire        [15:0] amplitude,  // measured amplitude over the gate
    output wire               gate_done   // one-cycle strobe at end of each gate
);
```

`error_count` feeds `pid_controller`; `gate_done` clocks the PID, streaming buffer, and lock
machine. `freq_counter` (reference) and `lock_in` (stub) both conform.

## 4. Streaming record format

`streaming_buffer` writes one record of `words_per_record` × `data_width` per `gate_done`,
into the circular BRAM at `bram_base`. The default (spin-controller) layout is 4 words
`(freq_raw, freq_dec, amp_raw, amp_dec)`; a design may redefine it, and the host
`StreamReader(fields=...)` must be told the matching layout. Bit 31 of word 0 is reserved as
the multi-board `sync_flag`.

## 5. Host API

`host/rp_optomech/board.py::BoardSession(ip, regs)` — `regs` is the generated
`registers_<name>` module. Access is by **name**: `read(name)`, `write(name, value)`,
`read_field(name, field)`, `write_field(name, field, value)`, `read_bram(offset, count)`.
The host never hard-codes an offset. Wire protocol to the board daemon: line-oriented
`R`/`W`/`RB`/`PING`/`QUIT` (see `daemon.py`).

---

## Path ownership map

No two work packages own overlapping paths. Interface/shared files are owned by the
orchestrator only.

| Path | Owner |
|------|-------|
| `regspec/regspec.py`, `regspec/generators/`, `regspec/SCHEMA.md` | orchestrator (the schema is a frozen contract) |
| `regspec/specs/<design>.yaml` | the design's owner |
| `regspec/generated/` | generated — no human owner (CI-checked) |
| `rtl/io`, `rtl/dsp`, `rtl/feedback`, `rtl/infra` | RTL-library WP |
| `rtl/measurement/INTERFACE.md` | orchestrator (frozen contract) |
| `rtl/measurement/<impl>.v` | the measurement-block WP |
| `host/rp_optomech/` | host WP |
| `examples/<experiment>/` | that experiment's WP |
| `docs/`, `roles/`, `CLAUDE.md`, `README.md` | orchestrator |
