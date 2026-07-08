#!/usr/bin/env bash
#
# check_all.sh — one command to verify the whole framework. CI entry point.
#
#   1. every register spec regenerates identically (no drift)  -> gen_all --check
#   2. host package tests                                       -> pytest
#   3. generated regfile + RTL library testbenches             -> run_sims.sh
#
# Needs: python (+ PyYAML, numpy, pytest) and iverilog/vvp on PATH.
# Usage:  scripts/check_all.sh
#
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== [1/3] register-spec codegen is in sync =="
for spec in regspec/specs/*.yaml; do
    python regspec/gen_all.py "$spec" --check >/dev/null && echo "  in sync: $spec"
done

echo ""
echo "== [2/3] host package tests =="
python -m pytest host/rp_optomech/tests/ -q

echo ""
echo "== [3/3] register file + RTL simulations =="
bash scripts/run_sims.sh

echo ""
echo "== ALL CHECKS PASSED =="
