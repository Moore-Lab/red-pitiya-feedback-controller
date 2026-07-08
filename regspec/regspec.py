"""Register-spec loader, validator, and offset allocator.

This is the single source of truth for a Red Pitaya feedback design's AXI
register bank. One YAML spec is parsed into a flat, validated list of concrete
registers that the code generators (Verilog / Python / Markdown) consume. No
hand-duplication: the Verilog register file, the host Python constants, and the
docs table are all generated from the same object graph.

Spec schema (see regspec/specs/core.yaml for a worked example and
regspec/SCHEMA.md for the full reference):

    meta:
      name: <identifier>          # used for generated module / file names
      description: <str>
      base_address: 0x40000000
      data_width: 32              # bits per register (word size)
    registers:                    # shared / global registers
      - name: <identifier>
        access: rw | ro           # wo is treated as rw with no readback guarantee
        offset: <int>             # optional; auto-allocated in list order if omitted
        reset: <int>              # default 0 (rw reset value, or the const for ro)
        source: input | const     # ro only: 'input' = PL-driven port, 'const' = reset
        description: <str>
        fields:                   # optional bitfields
          - {name: <id>, bits: <int> | [lsb, msb], description: <str>}
    channels:                     # optional per-channel replication block
      count: <int>
      format: "{name}_{i}"        # naming template; default "{name}_ch{i}"
      start_index: 0
      registers: [ ... same shape as above ... ]

Allocation order: shared registers first (in listed order), then the channel
block laid out channel-by-channel (all of channel 0's registers, then channel
1's, ...). Explicit offsets are honoured and validated for overlap/alignment;
omitted offsets are packed into the next free aligned word.
"""

from __future__ import annotations

import dataclasses
from dataclasses import dataclass, field
from typing import Optional

try:
    import yaml
except ImportError as exc:  # pragma: no cover - dev-side dependency
    raise SystemExit(
        "regspec needs PyYAML on the development machine: pip install pyyaml"
    ) from exc


class SpecError(ValueError):
    """Raised for any malformed or inconsistent register spec."""


@dataclass
class Field:
    name: str
    lsb: int
    msb: int
    description: str = ""

    @property
    def width(self) -> int:
        return self.msb - self.lsb + 1

    @property
    def mask(self) -> int:
        return ((1 << self.width) - 1) << self.lsb


@dataclass
class Register:
    name: str            # fully-resolved name (channel suffix already applied)
    access: str          # "rw" or "ro"
    offset: int          # byte offset from base_address
    reset: int = 0
    source: str = "const"  # ro only: "input" (PL port) or "const"
    description: str = ""
    fields: list = field(default_factory=list)
    base_name: Optional[str] = None  # unsuffixed name for channel registers
    channel: Optional[int] = None    # channel index, or None for shared registers

    @property
    def is_input(self) -> bool:
        return self.access == "ro" and self.source == "input"

    @property
    def is_const(self) -> bool:
        return self.access == "ro" and self.source == "const"


@dataclass
class RegSpec:
    name: str
    description: str
    base_address: int
    data_width: int
    registers: list  # list[Register], sorted by offset

    @property
    def word_bytes(self) -> int:
        return self.data_width // 8

    @property
    def addr_span(self) -> int:
        """Smallest power-of-two byte span covering every register."""
        top = max((r.offset for r in self.registers), default=0) + self.word_bytes
        span = 1
        while span < top:
            span <<= 1
        return span

    @property
    def addr_width(self) -> int:
        return max(1, (self.addr_span - 1).bit_length())


# --- parsing helpers ------------------------------------------------------

def _as_int(value, ctx: str) -> int:
    """Accept ints or hex/dec strings ('0x40', '64')."""
    if isinstance(value, bool):
        raise SpecError("{}: expected an integer, got a bool".format(ctx))
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        try:
            return int(value, 0)
        except ValueError:
            pass
    raise SpecError("{}: cannot parse integer from {!r}".format(ctx, value))


def _parse_fields(raw_fields, ctx: str) -> list:
    out = []
    for i, rf in enumerate(raw_fields or []):
        fctx = "{} field[{}]".format(ctx, i)
        if "name" not in rf:
            raise SpecError(fctx + ": missing 'name'")
        bits = rf.get("bits")
        if bits is None:
            raise SpecError(fctx + ": missing 'bits'")
        if isinstance(bits, (list, tuple)):
            if len(bits) != 2:
                raise SpecError(fctx + ": 'bits' list must be [lsb, msb]")
            lsb = _as_int(bits[0], fctx)
            msb = _as_int(bits[1], fctx)
        else:
            lsb = msb = _as_int(bits, fctx)
        if lsb > msb:
            lsb, msb = msb, lsb
        out.append(Field(name=rf["name"], lsb=lsb, msb=msb,
                         description=rf.get("description", "")))
    return out


def _parse_register(raw, ctx: str, base_name=None, channel=None) -> Register:
    if "name" not in raw:
        raise SpecError(ctx + ": register missing 'name'")
    name = raw["name"]
    access = raw.get("access", "rw")
    if access not in ("rw", "ro", "wo"):
        raise SpecError("{} '{}': access must be rw|ro|wo".format(ctx, name))
    if access == "wo":
        access = "rw"  # generator treats write-only as rw with best-effort readback
    source = raw.get("source", "const" if access == "ro" else "n/a")
    if access == "ro" and source not in ("input", "const"):
        raise SpecError("{} '{}': ro source must be 'input' or 'const'".format(ctx, name))
    offset = None if "offset" not in raw else _as_int(raw["offset"], ctx)
    reset = _as_int(raw.get("reset", 0), "{} '{}' reset".format(ctx, name))
    return Register(
        name=name, access=access, offset=offset if offset is not None else -1,
        reset=reset, source=source, description=raw.get("description", ""),
        fields=_parse_fields(raw.get("fields"), "{} '{}'".format(ctx, name)),
        base_name=base_name, channel=channel,
    )


def _expand_channels(raw_channels: dict) -> list:
    count = _as_int(raw_channels.get("count", 0), "channels.count")
    fmt = raw_channels.get("format", "{name}_ch{i}")
    start = _as_int(raw_channels.get("start_index", 0), "channels.start_index")
    templ = raw_channels.get("registers", [])
    out = []
    for ch in range(start, start + count):
        for raw in templ:
            reg = _parse_register(raw, "channels", base_name=raw["name"], channel=ch)
            reg.name = fmt.format(name=raw["name"], i=ch)
            out.append(reg)
    return out


# --- allocation + validation ---------------------------------------------

def _allocate(regs: list, word_bytes: int) -> None:
    """Assign concrete byte offsets to any register with offset == -1 and
    validate the whole set for alignment and overlap. Mutates in place."""
    occupied = {}  # offset -> register name

    # First place the explicit offsets.
    for r in regs:
        if r.offset >= 0:
            if r.offset % word_bytes != 0:
                raise SpecError(
                    "register '{}' offset 0x{:x} not aligned to {} bytes".format(
                        r.name, r.offset, word_bytes))
            if r.offset in occupied:
                raise SpecError(
                    "offset 0x{:x} used by both '{}' and '{}'".format(
                        r.offset, occupied[r.offset], r.name))
            occupied[r.offset] = r.name

    # Then pack the auto ones into the lowest free aligned slots, in list order.
    cursor = 0
    for r in regs:
        if r.offset < 0:
            while cursor in occupied:
                cursor += word_bytes
            r.offset = cursor
            occupied[cursor] = r.name
            cursor += word_bytes


def load(path: str) -> RegSpec:
    with open(path, "r", encoding="utf-8") as fh:
        doc = yaml.safe_load(fh)
    if not isinstance(doc, dict):
        raise SpecError("top level of spec must be a mapping")

    meta = doc.get("meta", {})
    for key in ("name", "base_address", "data_width"):
        if key not in meta:
            raise SpecError("meta missing required key '{}'".format(key))
    data_width = _as_int(meta["data_width"], "meta.data_width")
    if data_width % 8 != 0:
        raise SpecError("meta.data_width must be a multiple of 8")

    regs = [_parse_register(r, "registers") for r in doc.get("registers", [])]
    if "channels" in doc:
        regs += _expand_channels(doc["channels"])
    if not regs:
        raise SpecError("spec defines no registers")

    # Validate duplicate names + field bounds before allocating.
    seen = set()
    for r in regs:
        if r.name in seen:
            raise SpecError("duplicate register name '{}'".format(r.name))
        seen.add(r.name)
        for f in r.fields:
            if f.msb >= data_width:
                raise SpecError(
                    "register '{}' field '{}' bit {} exceeds data_width {}".format(
                        r.name, f.name, f.msb, data_width))

    _allocate(regs, data_width // 8)
    regs.sort(key=lambda r: r.offset)

    return RegSpec(
        name=meta["name"],
        description=meta.get("description", ""),
        base_address=_as_int(meta["base_address"], "meta.base_address"),
        data_width=data_width,
        registers=regs,
    )


if __name__ == "__main__":
    import sys
    spec = load(sys.argv[1])
    print("spec '{}': {} registers, base 0x{:08x}, span {} B ({} addr bits)".format(
        spec.name, len(spec.registers), spec.base_address,
        spec.addr_span, spec.addr_width))
    for r in spec.registers:
        tag = r.access + ("/in" if r.is_input else "/const" if r.is_const else "")
        print("  0x{:03x}  {:<28s} {:<8s} reset=0x{:x}".format(
            r.offset, r.name, tag, r.reset))
