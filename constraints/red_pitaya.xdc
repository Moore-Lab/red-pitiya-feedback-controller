# Red Pitaya board pinout constraints (XDC)  [FRAMEWORK REFERENCE]
# Part: xc7z020clg400-1   (Gen-2 STEMlab 65-16 TI — retargeted from xc7z010clg400-1 / 125-14)
# Pin assignments per Pavel Demin's red-pitaya-notes/cfg/ports.xdc.
#
# WP-SYNC retarget scope: this framework reference is retargeted to the Zynq-7020
# (xc7z020clg400-1) part, and the DAISY block is retargeted from the original-gen
# SATA/DAISY connector to the Gen-2 S1/S2 daisy connector (Daisy_IO, 1V8). The
# clg400 package is common to the 7010 and 7020, so the ADC-clock / ADC-data /
# DAC / LED package pins below remain valid on the 7020 and are left as the shared
# Red Pitaya pinout. The 65-16 TI's board-specific ADC/DAC pin + IOSTANDARD deltas
# (16-bit ADC, DC-coupled front end) belong to the per-board XDCs (fpga/board_a,
# fpga/board_b — WP-BD-A/B), not to this sync retarget.
#
# This is the design-INDEPENDENT board pinout: ADC clock, ADC A/B data, DAC data +
# control, the S1/S2 daisy multi-board trigger sync pair, and the 8 LEDs. Any
# framework design reuses it as-is; the top-level port names below (adc_clk_p/n,
# adc_dat_a/b, dac_dat, daisy_p/n_o/i, led_o) are the names a generated top / block
# design must present. Comment out blocks a given design does not use (e.g. daisy_*
# for single-board designs) to avoid unplaced-port DRCs.
#
# The ADC/DAC/LED pinout is verified in the reference spin controller
# (red-pitiya-spin-controller). The DAISY block below implements trigger sync
# (see sync_io.v); its physical S1/S2 routing is a Batch-2 hardware gate (below).
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

# ─── S1/S2 daisy connector (Gen-2 multi-board trigger sync, Path A) ──────────
# Gen-2 retarget of the original-gen SATA/DAISY sync pair. Transports the master
# board's freq_counter.gate_done pulse to the slave board's sync_io over one
# Daisy_IO differential pair (1V8, up to 500 Mb/s) on the S1/S2 connector. The
# scalar port names (daisy_p/n_o = one TX pair to S2, daisy_p/n_i = one RX pair
# from S1) are unchanged so sync_io.v and WP-BD-A/B wire the four daisy ports
# unchanged; the remaining Daisy_IO pairs are left unconstrained for future use.
#
# IOSTANDARD — DIFF_HSTL_I_18: the S1/S2 Daisy_IO class is 1V8 differential.
# On this part (xc7z020clg400-1, all HR I/O banks) the valid 1V8 differential
# standard is DIFF_HSTL_I_18 — the same standard as the ADC-clock pair, and the
# bench-verified Gen-1 setting. Native LVDS is deliberately NOT used: 7-series
# HR banks only offer LVDS_25 (which forces the bank VCCO to 2.5 V for the OBUFDS
# output), conflicting with the 1.8 V daisy/ADC bank and failing DRC. This
# matches the IBUFDS/OBUFDS IOSTANDARD in rtl/infra/sync_io.v — keep the two in step.
#
# HARDWARE GATE (Batch 2 — Decision D-A2, NOT this package): the pin LOCs below
# are the verified Red Pitaya daisy differential pairs on the clg400 package
# (guaranteed-valid diff pairs, so FPGA-internal DRC is clean). Whether they
# reach the second board via the *X-channel 2.0 Click Shield* (shared oscillator,
# out-of-the-box — the assumed default) or via *direct S1/S2 cabling* (which may
# need a secondary-board HW mod) is a Batch-2 hardware-bring-up decision, and the
# exact 65-16 TI board-file LOCs must be confirmed against that choice on the
# device machine. The Vivado DRC gate (fpga/drc_gen2.tcl) validates FPGA-internal
# legality here; physical routing is validated at Batch-2 bring-up.
#
# Termination: if the IBUFDS input chatters when the daisy link is unplugged, the
# slave-side input may need a pull-down or differential termination — DIFF_HSTL_I_18
# has no implicit DIFF_TERM. Verify behaviour before adding any termination property.

set_property PACKAGE_PIN T12 [get_ports daisy_p_o]
set_property PACKAGE_PIN U12 [get_ports daisy_n_o]
set_property IOSTANDARD DIFF_HSTL_I_18 [get_ports daisy_p_o]
set_property IOSTANDARD DIFF_HSTL_I_18 [get_ports daisy_n_o]

set_property PACKAGE_PIN P14 [get_ports daisy_p_i]
set_property PACKAGE_PIN R14 [get_ports daisy_n_i]
set_property IOSTANDARD DIFF_HSTL_I_18 [get_ports daisy_p_i]
set_property IOSTANDARD DIFF_HSTL_I_18 [get_ports daisy_n_i]

# The daisy-IN signal is asynchronous to the local adc_clk — it's driven by the
# master board's freq_counter.gate_done, in a different (free-running) clock
# domain. The 2-FF synchroniser at sync_io.v's input (ASYNC_REG = TRUE) handles
# the clock-domain crossing. The set_false_path below documents that intent so
# Vivado doesn't time the cross-clock path and STA doesn't carry a misleading
# "Slack: inf" line for the input.
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
