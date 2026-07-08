"""Unit tests for the register-spec loader / allocator / validator (the crown jewel).

Covers offset auto-allocation, explicit offsets, channel expansion, field parsing, the
ro input/const classification, and every SpecError path. Run: pytest regspec/tests/
"""

import os
import textwrap

import pytest

import regspec


def write(tmp_path, text):
    p = tmp_path / "spec.yaml"
    p.write_text(textwrap.dedent(text), encoding="utf-8")
    return str(p)


# --- happy paths ---------------------------------------------------------

def test_core_yaml_shape():
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    spec = regspec.load(os.path.join(root, "regspec", "specs", "core.yaml"))
    assert spec.name == "core"
    assert len(spec.registers) == 25          # 9 shared + 2 * 8 channel
    by_name = {r.name: r for r in spec.registers}
    assert by_name["magic"].offset == 0x04
    assert by_name["magic"].is_const
    assert by_name["buffer_write_ptr"].is_input
    # channels laid out block-by-block after the shared header
    assert by_name["nco_tuning_word_ch0"].offset == 0x24
    assert by_name["nco_tuning_word_ch1"].offset == 0x44


def test_auto_allocation_is_sequential(tmp_path):
    spec = regspec.load(write(tmp_path, """
        meta: {name: t, base_address: 0x40000000, data_width: 32}
        registers:
          - {name: a, access: rw}
          - {name: b, access: rw}
          - {name: c, access: ro, source: const, reset: 0x5}
    """))
    offs = [r.offset for r in spec.registers]
    assert offs == [0x00, 0x04, 0x08]


def test_explicit_offsets_honoured_and_packed_around(tmp_path):
    spec = regspec.load(write(tmp_path, """
        meta: {name: t, base_address: 0x0, data_width: 32}
        registers:
          - {name: a, access: rw}            # auto -> 0x00
          - {name: pinned, access: rw, offset: 0x10}
          - {name: b, access: rw}            # auto -> lowest free = 0x04
    """))
    by = {r.name: r.offset for r in spec.registers}
    assert by["a"] == 0x00 and by["pinned"] == 0x10 and by["b"] == 0x04


def test_channel_format_and_indexing(tmp_path):
    spec = regspec.load(write(tmp_path, """
        meta: {name: t, base_address: 0x0, data_width: 32}
        registers:
          - {name: ctrl, access: rw}
        channels:
          count: 3
          format: "{name}_{i}"
          start_index: 1
          registers:
            - {name: gain, access: rw}
    """))
    names = [r.name for r in spec.registers]
    assert names == ["ctrl", "gain_1", "gain_2", "gain_3"]


def test_fields_parsed_lsb_msb_order_insensitive(tmp_path):
    spec = regspec.load(write(tmp_path, """
        meta: {name: t, base_address: 0x0, data_width: 32}
        registers:
          - name: r
            access: rw
            fields:
              - {name: lo, bits: 0}
              - {name: hi, bits: [31, 16]}   # given msb,lsb — should normalise
    """))
    f = {fld.name: fld for fld in spec.registers[0].fields}
    assert f["lo"].lsb == 0 and f["lo"].msb == 0 and f["lo"].mask == 0x1
    assert f["hi"].lsb == 16 and f["hi"].msb == 31 and f["hi"].mask == 0xFFFF0000


# --- error paths ---------------------------------------------------------

def test_duplicate_name_rejected(tmp_path):
    with pytest.raises(regspec.SpecError):
        regspec.load(write(tmp_path, """
            meta: {name: t, base_address: 0x0, data_width: 32}
            registers:
              - {name: dup, access: rw}
              - {name: dup, access: rw}
        """))


def test_offset_collision_rejected(tmp_path):
    with pytest.raises(regspec.SpecError):
        regspec.load(write(tmp_path, """
            meta: {name: t, base_address: 0x0, data_width: 32}
            registers:
              - {name: a, access: rw, offset: 0x10}
              - {name: b, access: rw, offset: 0x10}
        """))


def test_unaligned_offset_rejected(tmp_path):
    with pytest.raises(regspec.SpecError):
        regspec.load(write(tmp_path, """
            meta: {name: t, base_address: 0x0, data_width: 32}
            registers:
              - {name: a, access: rw, offset: 0x02}
        """))


def test_field_beyond_data_width_rejected(tmp_path):
    with pytest.raises(regspec.SpecError):
        regspec.load(write(tmp_path, """
            meta: {name: t, base_address: 0x0, data_width: 32}
            registers:
              - {name: a, access: rw, fields: [{name: x, bits: 32}]}
        """))


def test_missing_meta_key_rejected(tmp_path):
    with pytest.raises(regspec.SpecError):
        regspec.load(write(tmp_path, """
            meta: {name: t, data_width: 32}
            registers:
              - {name: a, access: rw}
        """))


def test_bad_ro_source_rejected(tmp_path):
    with pytest.raises(regspec.SpecError):
        regspec.load(write(tmp_path, """
            meta: {name: t, base_address: 0x0, data_width: 32}
            registers:
              - {name: a, access: ro, source: nonsense}
        """))
