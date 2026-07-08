# Red Pitaya STEMlab 125-14 — board pinout constraints (XDC)  [FRAMEWORK REFERENCE]
# Part: xc7z010clg400-1
# Pin assignments per Pavel Demin's red-pitaya-notes/cfg/ports.xdc.
#
# This is the design-INDEPENDENT board pinout for the STEMlab 125-14: ADC clock,
# ADC A/B data, DAC data + control, the DAISY (SATA-connector) multi-board trigger
# sync pair, and the 8 LEDs. Any framework design reuses it as-is; the top-level
# port names below (adc_clk_p/n, adc_dat_a/b, dac_dat, daisy_p/n_o/i, led_o) are the
# names a generated top / block design must present. Comment out blocks a given
# design does not use (e.g. daisy_* for single-board designs) to avoid unplaced-port DRCs.
#
# Verified in the reference spin controller (red-pitiya-spin-controller). The DAISY
# block below is what implements trigger sync over the SATA connector (see sync_io.v).
#
# Note on ADC bit ordering: the LTC2145-14 routes its 14-bit output to FPGA
# pins that Pavel Demin labels bits 2..15 of a 16-bit bus (bits 0..1 unused).
# Our 14-bit port maps adc_dat[0] = Demin's bit 2 (LSB) → adc_dat[13] = bit 15 (MSB).

# ─── ADC clock (LTC2145, differential HSTL @ 125 MHz) ────────────────────────
set_property PACKAGE_PIN U18 [get_ports adc_clk_p]
set_property PACKAGE_PIN U19 [get_ports adc_clk_n]
set_property IOSTANDARD DIFF_HSTL_I_18 [get_ports adc_clk_p]
set_property IOSTANDARD DIFF_HSTL_I_18 [get_ports adc_clk_n]
create_clock -name adc_clk -period 8.000 [get_ports adc_clk_p]

# ─── ADC channel A data (LVCMOS18) ───────────────────────────────────────────
set_property PACKAGE_PIN Y17 [get_ports {adc_dat_a[0]}]
set_property PACKAGE_PIN W16 [get_ports {adc_dat_a[1]}]
set_property PACKAGE_PIN Y16 [get_ports {adc_dat_a[2]}]
set_property PACKAGE_PIN W15 [get_ports {adc_dat_a[3]}]
set_property PACKAGE_PIN W14 [get_ports {adc_dat_a[4]}]
set_property PACKAGE_PIN Y14 [get_ports {adc_dat_a[5]}]
set_property PACKAGE_PIN W13 [get_ports {adc_dat_a[6]}]
set_property PACKAGE_PIN V12 [get_ports {adc_dat_a[7]}]
set_property PACKAGE_PIN V13 [get_ports {adc_dat_a[8]}]
set_property PACKAGE_PIN T14 [get_ports {adc_dat_a[9]}]
set_property PACKAGE_PIN T15 [get_ports {adc_dat_a[10]}]
set_property PACKAGE_PIN V15 [get_ports {adc_dat_a[11]}]
set_property PACKAGE_PIN T16 [get_ports {adc_dat_a[12]}]
set_property PACKAGE_PIN V16 [get_ports {adc_dat_a[13]}]
set_property IOSTANDARD LVCMOS18 [get_ports {adc_dat_a[*]}]

# ─── ADC channel B data (LVCMOS18) ───────────────────────────────────────────
set_property PACKAGE_PIN R18 [get_ports {adc_dat_b[0]}]
set_property PACKAGE_PIN P16 [get_ports {adc_dat_b[1]}]
set_property PACKAGE_PIN P18 [get_ports {adc_dat_b[2]}]
set_property PACKAGE_PIN N17 [get_ports {adc_dat_b[3]}]
set_property PACKAGE_PIN R19 [get_ports {adc_dat_b[4]}]
set_property PACKAGE_PIN T20 [get_ports {adc_dat_b[5]}]
set_property PACKAGE_PIN T19 [get_ports {adc_dat_b[6]}]
set_property PACKAGE_PIN U20 [get_ports {adc_dat_b[7]}]
set_property PACKAGE_PIN V20 [get_ports {adc_dat_b[8]}]
set_property PACKAGE_PIN W20 [get_ports {adc_dat_b[9]}]
set_property PACKAGE_PIN W19 [get_ports {adc_dat_b[10]}]
set_property PACKAGE_PIN Y19 [get_ports {adc_dat_b[11]}]
set_property PACKAGE_PIN W18 [get_ports {adc_dat_b[12]}]
set_property PACKAGE_PIN Y18 [get_ports {adc_dat_b[13]}]
set_property IOSTANDARD LVCMOS18 [get_ports {adc_dat_b[*]}]

# ─── DAC data (AD9767 interleaved bus, LVCMOS33) ─────────────────────────────
set_property PACKAGE_PIN M19 [get_ports {dac_dat[0]}]
set_property PACKAGE_PIN M20 [get_ports {dac_dat[1]}]
set_property PACKAGE_PIN L19 [get_ports {dac_dat[2]}]
set_property PACKAGE_PIN L20 [get_ports {dac_dat[3]}]
set_property PACKAGE_PIN K19 [get_ports {dac_dat[4]}]
set_property PACKAGE_PIN J19 [get_ports {dac_dat[5]}]
set_property PACKAGE_PIN J20 [get_ports {dac_dat[6]}]
set_property PACKAGE_PIN H20 [get_ports {dac_dat[7]}]
set_property PACKAGE_PIN G19 [get_ports {dac_dat[8]}]
set_property PACKAGE_PIN G20 [get_ports {dac_dat[9]}]
set_property PACKAGE_PIN F19 [get_ports {dac_dat[10]}]
set_property PACKAGE_PIN F20 [get_ports {dac_dat[11]}]
set_property PACKAGE_PIN D20 [get_ports {dac_dat[12]}]
set_property PACKAGE_PIN D19 [get_ports {dac_dat[13]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_dat[*]}]

# ─── DAC control (LVCMOS33) ──────────────────────────────────────────────────
set_property PACKAGE_PIN M17 [get_ports dac_wrt]
set_property PACKAGE_PIN N16 [get_ports dac_sel]
set_property PACKAGE_PIN M18 [get_ports dac_clk_o]
set_property PACKAGE_PIN N15 [get_ports dac_rst]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_wrt dac_sel dac_clk_o dac_rst}]

# ─── DAISY connector (multi-board trigger sync, Path A) ─────────────────────
# LVDS-style differential pair on the SATA connector, used to transport the
# master board's freq_counter.gate_done pulse to the slave board's sync_io.
# Pair [0] only; pair [1] is left unconstrained for future use.
#
# IOSTANDARD: Pavel Demin's red-pitaya-notes/cfg/ports.xdc uses DIFF_HSTL_I_18
# (the same 1.8 V differential standard as the ADC clock pair). The brief in
# docs/multi_board_trigger_sync.md §8 said LVDS_25 — that was incorrect;
# DIFF_HSTL_I_18 is the verified setting for this hardware.
#
# If §3.2 of docs/multi_board_test_plan.md shows the IBUFDS input chattering
# when the SATA cable is unplugged, the slave-side IBUFDS may need a pull-down
# or differential termination — DIFF_HSTL_I_18 does not include the explicit
# DIFF_TERM property that LVDS_25 does. Verify behaviour before adding any
# termination property.

set_property PACKAGE_PIN T12 [get_ports daisy_p_o]
set_property PACKAGE_PIN U12 [get_ports daisy_n_o]
set_property IOSTANDARD DIFF_HSTL_I_18 [get_ports daisy_p_o]
set_property IOSTANDARD DIFF_HSTL_I_18 [get_ports daisy_n_o]

set_property PACKAGE_PIN P14 [get_ports daisy_p_i]
set_property PACKAGE_PIN R14 [get_ports daisy_n_i]
set_property IOSTANDARD DIFF_HSTL_I_18 [get_ports daisy_p_i]
set_property IOSTANDARD DIFF_HSTL_I_18 [get_ports daisy_n_i]

# The DAISY-IN signal is asynchronous to the local adc_clk — it's driven by
# the master board's freq_counter.gate_done, which is in a different
# (free-running) clock domain. The 2-FF synchroniser at sync_io.v's input
# (with ASYNC_REG = TRUE) handles the clock-domain crossing. The
# set_false_path below documents this intent so Vivado doesn't waste effort
# timing the cross-clock path, and the static-timing report doesn't carry
# a misleading "Slack: inf" line for the input.
set_false_path -from [get_ports daisy_p_i] -to [all_clocks]

# ─── LEDs (PL fabric, 3.3 V, active high) ────────────────────────────────────
set_property PACKAGE_PIN F16 [get_ports {led_o[0]}]
set_property PACKAGE_PIN F17 [get_ports {led_o[1]}]
set_property PACKAGE_PIN G15 [get_ports {led_o[2]}]
set_property PACKAGE_PIN H15 [get_ports {led_o[3]}]
set_property PACKAGE_PIN K14 [get_ports {led_o[4]}]
set_property PACKAGE_PIN G14 [get_ports {led_o[5]}]
set_property PACKAGE_PIN J15 [get_ports {led_o[6]}]
set_property PACKAGE_PIN J16 [get_ports {led_o[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_o[*]}]
