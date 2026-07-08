#!/usr/bin/env bash
#
# run_sims.sh — compile + run every Icarus testbench in the framework and report.
#
# Covers the generated register file (regspec/) and the ported RTL library (rtl/).
# A test passes if its output contains "PASS" and no "FAIL". Exits non-zero on any
# failure (CI-friendly).
#
# Usage:  scripts/run_sims.sh            (needs iverilog + vvp on PATH)
#
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
IVERILOG="${IVERILOG:-iverilog}"
VVP="${VVP:-vvp}"
mkdir -p build

# Regenerate coefficient ROMs the DSP tbs need, into the sim working dir.
python rtl/dsp/gen_sine_lut.py   >/dev/null 2>&1 || true
python rtl/dsp/gen_fir_coeffs.py >/dev/null 2>&1 || true
cp -f rtl/dsp/sine_lut.mem   build/ 2>/dev/null || true
cp -f rtl/dsp/fir_coeffs.mem build/ 2>/dev/null || true

pass=0; fail=0; failed_list=""

# run <name> <defines> <vvp_cwd> <sources...>
run() {
    local name="$1"; local defs="$2"; local wd="$3"; shift 3
    local out="$ROOT/build/$name.out"
    if ! $IVERILOG -g2012 $defs -o "$out" "$@" >"build/$name.compile.log" 2>&1; then
        echo "  COMPILE FAIL: $name"; sed 's/^/    /' "build/$name.compile.log" | head -6
        fail=$((fail+1)); failed_list="$failed_list $name"; return
    fi
    local result
    result="$( cd "$wd" && $VVP "$out" 2>&1 )"
    if echo "$result" | grep -q "PASS" && ! echo "$result" | grep -q "FAIL"; then
        echo "  PASS: $name"; pass=$((pass+1))
    else
        echo "  FAIL: $name"; echo "$result" | grep -iE "fail|error" | head -4 | sed 's/^/    /'
        fail=$((fail+1)); failed_list="$failed_list $name"
    fi
}

echo "== generated register file =="
run tb_regfile          ""      "$ROOT"       regspec/tb/tb_regfile.v regspec/generated/core_regs.v

echo "== rtl library =="
run tb_blinker          ""      "$ROOT"       rtl/tb/tb_blinker.v          rtl/infra/blinker.v
run tb_cic_decimator    ""      "$ROOT"       rtl/tb/tb_cic_decimator.v    rtl/dsp/cic_decimator.v
run tb_freq_counter     ""      "$ROOT"       rtl/tb/tb_freq_counter.v     rtl/measurement/freq_counter.v
run tb_lock_acquisition ""      "$ROOT"       rtl/tb/tb_lock_acquisition.v rtl/feedback/lock_acquisition.v
run tb_pid_controller   ""      "$ROOT"       rtl/tb/tb_pid_controller.v   rtl/feedback/pid_controller.v
run tb_streaming_buffer ""      "$ROOT"       rtl/tb/tb_streaming_buffer.v rtl/infra/streaming_buffer.v
run tb_sync_io          "-DSIM" "$ROOT"       rtl/tb/tb_sync_io.v          rtl/infra/sync_io.v
run tb_dac_sine         ""      "$ROOT/build"  rtl/tb/tb_dac_sine.v         rtl/dsp/dac_sine.v
run tb_comp_fir         ""      "$ROOT/build"  rtl/tb/tb_comp_fir.v         rtl/dsp/comp_fir.v
run tb_nco_summer       ""      "$ROOT"       rtl/tb/tb_nco_summer.v       rtl/dsp/nco_summer.v
run tb_adc_mux          ""      "$ROOT"       rtl/tb/tb_adc_mux.v          rtl/io/adc_mux.v
run tb_sign_extend      ""      "$ROOT"       rtl/tb/tb_sign_extend_14to16.v rtl/io/sign_extend_14to16.v
run tb_lock_in          ""      "$ROOT/build"  rtl/tb/tb_lock_in.v          rtl/measurement/lock_in.v

echo "== lane integration =="
run tb_lane_datapath    ""      "$ROOT/build"  rtl/tb/tb_lane_datapath.v \
    rtl/dsp/nco_summer.v rtl/dsp/dac_sine.v rtl/io/sign_extend_14to16.v rtl/measurement/freq_counter.v
run tb_lane_closed_loop ""      "$ROOT/build"  rtl/tb/tb_lane_closed_loop.v \
    rtl/feedback/lock_acquisition.v rtl/feedback/pid_controller.v rtl/dsp/nco_summer.v \
    rtl/dsp/dac_sine.v rtl/io/sign_extend_14to16.v rtl/measurement/freq_counter.v

echo ""
echo "== $pass passed, $fail failed =="
if [ $fail -ne 0 ]; then echo "failed:$failed_list"; exit 1; fi
