"""One-shot code generator: register spec (YAML) -> Verilog + Python + Markdown.

This is the single command that keeps the three faces of the register map in
lockstep. Run it whenever a spec changes; commit the generated files.

Usage:
    python regspec/gen_all.py regspec/specs/core.yaml
    python regspec/gen_all.py regspec/specs/core.yaml --outdir build/core --check

Outputs (default: alongside sibling generated/ and host/ trees):
    regspec/generated/<name>_regs.v      the AXI4-Lite slave register file
    host/rp_optomech/registers_<name>.py the host/board Python register module
    regspec/generated/<name>_registers.md the docs table

--check exits non-zero if regenerating would change any committed output (use in
CI to prove the generated files are in sync with the spec).
"""

from __future__ import annotations

import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import regspec
from generators import gen_verilog, gen_python, gen_docs


def _write_or_check(path, content, check, changed):
    existing = None
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as fh:
            existing = fh.read()
    normalized_existing = existing.replace("\r\n", "\n") if existing is not None else None
    if check:
        if normalized_existing != content:
            print("OUT OF SYNC: {}".format(path))
            changed.append(path)
        else:
            print("ok: {}".format(path))
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(content)
    print("wrote {}".format(path))


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("spec", help="path to the register-spec YAML")
    p.add_argument("--outdir", default=None,
                   help="override output directory (default: repo generated/ + host/ trees)")
    p.add_argument("--check", action="store_true",
                   help="don't write; exit non-zero if anything would change")
    args = p.parse_args(argv)

    spec = regspec.load(args.spec)
    print("spec '{}': {} registers, base 0x{:08x}, span 0x{:x}".format(
        spec.name, len(spec.registers), spec.base_address, spec.addr_span))

    verilog = gen_verilog.generate(spec)
    python = gen_python.generate(spec)
    docs = gen_docs.generate(spec)

    if args.outdir:
        v_path = os.path.join(args.outdir, "{}_regs.v".format(spec.name))
        py_path = os.path.join(args.outdir, "registers_{}.py".format(spec.name))
        md_path = os.path.join(args.outdir, "{}_registers.md".format(spec.name))
    else:
        v_path = os.path.join(ROOT, "regspec", "generated", "{}_regs.v".format(spec.name))
        py_path = os.path.join(ROOT, "host", "rp_optomech", "registers_{}.py".format(spec.name))
        md_path = os.path.join(ROOT, "regspec", "generated", "{}_registers.md".format(spec.name))

    changed = []
    _write_or_check(v_path, verilog, args.check, changed)
    _write_or_check(py_path, python, args.check, changed)
    _write_or_check(md_path, docs, args.check, changed)

    if args.check and changed:
        print("\n{} file(s) out of sync — run: python regspec/gen_all.py {}".format(
            len(changed), args.spec))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
