# Register-spec schema

The register spec is the single source of truth for a design's AXI register bank. One YAML
file generates the Verilog register file, the host Python module, and the docs table. This is
the authoritative reference; [`specs/core.yaml`](specs/core.yaml) is a worked template.

## Top level

```yaml
meta:            # required
  name: <identifier>          # used for generated module/file names (e.g. spin_controller)
  description: <string>       # optional, one paragraph
  base_address: 0x40000000    # AXI base of the register region
  data_width: 32              # bits per register word (multiple of 8)

registers:       # optional list of shared/global registers
  - <register> ...

channels:        # optional: a lane template replicated per channel
  count: <int>
  format: "{name}_ch{i}"      # naming template; {name}, {i} substituted. default "{name}_ch{i}"
  start_index: 0              # default 0
  registers:
    - <register> ...
```

## A register

```yaml
- name: <identifier>          # required; unique across the whole design (after channel suffixing)
  access: rw | ro | wo        # default rw. wo is treated as rw with best-effort readback.
  offset: 0x10                # optional. If omitted, auto-allocated (see below).
  reset: 0x0                  # default 0. For rw: the reset/power-on value.
                              #            For ro/const: the constant the read path returns.
  source: input | const       # ro only. 'input' = a PL-driven port <name>_i.
                              #           'const' = the read path returns `reset`. (default: const)
  description: <string>       # optional; flows into the docs table and the metadata dict.
  fields:                     # optional bitfields
    - name: <identifier>
      bits: 0                 # a single bit ...
      # bits: [16, 31]        # ... or [lsb, msb] (order-insensitive)
      description: <string>
```

### Access → generated hardware

| access / source | Verilog | Read path | Write path |
|-----------------|---------|-----------|------------|
| `rw` | storage reg + output port `<name>_o` | returns stored value | byte-strobed write |
| `ro` + `source: input` | input port `<name>_i` | returns the port | (none) |
| `ro` + `source: const` | none | returns `reset` constant | (none) |

## Offset allocation

- Explicit `offset:` values are honoured and validated: must be aligned to `data_width/8`
  bytes, and must not collide.
- Registers with no `offset:` are packed into the lowest free aligned word, **in list order**:
  shared `registers:` first, then the `channels:` block laid out channel-by-channel (all of
  channel `start_index`'s registers, then the next channel, …).
- The address span is rounded up to the next power of two; `ADDR_WIDTH` is derived from it.

## Channels

The `channels:` block declares a control lane once and stamps it out `count` times. Each
templated register `name` becomes `format.format(name=name, i=index)` — e.g. with the default
format, `pid_setpoint` → `pid_setpoint_ch0`, `pid_setpoint_ch1`, … Use this instead of
copy-pasting per-axis registers (which is exactly the manual step the source project flagged as
error-prone).

## Validation

`regspec.load()` raises `SpecError` on: missing `meta` keys, duplicate register names,
unaligned or colliding explicit offsets, field bits beyond `data_width`, and malformed
`bits`/`access`/`source` values. Run `python regspec/regspec.py <spec>` to print the resolved
map and catch errors early.
