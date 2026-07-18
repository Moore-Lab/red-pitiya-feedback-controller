# Red Pitaya board pinout constraints (XDC)  [FRAMEWORK REFERENCE]
# Part: xc7z020clg400-1   (Gen-2 STEMlab 65-16 TI — retargeted from xc7z010clg400-1 / 125-14)
# ADC/DAC/LED pin assignments per Pavel Demin's red-pitaya-notes/cfg/ports.xdc;
# the daisy pins are the authoritative Z20_ll (65-16 TI) board-file DAISY_IO LOCs.
#
# WP-SYNC retarget scope: this framework reference is retargeted to the Zynq-7020
# (xc7z020clg400-1) part, and the DAISY block is retargeted from the original-gen
# daisy link to the Gen-2 Z20_ll Daisy_IO connector (two 1V8 differential TX
# pairs + two RX pairs, DIFF_SSTL18_I). The clg400 package is common to the 7010
# and 7020, so the ADC-clock / ADC-data / DAC / LED package pins below remain
# valid on the 7020 and are left as the shared Red Pitaya pinout. The 65-16 TI's
# board-specific ADC/DAC pin + IOSTANDARD deltas (16-bit ADC, DC-coupled front
# end) belong to the per-board XDCs (fpga/board_a, fpga/board_b — WP-BD-A/B), not
# to this sync retarget.
#
# This is the design-INDEPENDENT board pinout: ADC clock, ADC A/B data, DAC data +
# control, the Daisy_IO multi-board trigger sync pairs, and the 8 LEDs. Any
# framework design reuses it as-is; the top-level port names below (adc_clk_p/n,
# adc_dat_a/b, dac_dat, daisy_p/n_o[1:0], daisy_p/n_i[1:0], led_o) are the names a
# generated top / block design must present. Comment out blocks a given design
# does not use (e.g. daisy_* for single-board designs) to avoid unplaced-port DRCs.
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

# ─── Daisy_IO connector (Gen-2 multi-board trigger sync, Path A) ─────────────
# Gen-2 (Z20_ll / 65-16 TI) retarget of the original-gen daisy sync link. The
# authoritative Z20_ll board file exposes the Daisy_IO (S1/S2 SATA) connector as
# TWO output pairs + TWO input pairs, so the top-level ports are the [1:0] two-
# pair buses sync_io.v presents (WP-BD-A/B wire them unchanged):
#
#     daisy_p_o[0]/n_o[0]  V6/W6   DAISY_IO0   TX pair 0  (trigger — active)
#     daisy_p_o[1]/n_o[1]  U7/V7   DAISY_IO1   TX pair 1  (reserved — idled)
#     daisy_p_i[0]/n_i[0]  T5/U5   DAISY_IO2   RX pair 0  (trigger — active)
#     daisy_p_i[1]/n_i[1]  T9/U10  DAISY_IO3   RX pair 1  (reserved)
#
# The trigger transports the master board's freq_counter.gate_done pulse to the
# slave's sync_io over pair index [0] in each direction. Pair index [1] is the
# stock Red-Pitaya daisy-clock pair; this design forwards no sample clock, so
# sync_io idles TX[1] and does not receive on RX[1] (see rtl/infra/sync_io.v).
#
# Pin LOCs are the authoritative Z20_ll assignments (Red Pitaya
# STEMlab 65-16 TI board file, DAISY_IO0..3) — not invented, not Gen-1.
#
# IOSTANDARD — DIFF_SSTL18_I: the Z20_ll board file assigns the Daisy_IO diff
# pairs (and the ADC data/clock diff inputs) the 1V8 DIFF_SSTL18_I class. Native
# LVDS is deliberately NOT used: 7-series HR banks only offer LVDS_25 (which
# forces the bank VCCO to 2.5 V for the OBUFDS output), conflicting with the
# 1.8 V daisy bank and failing DRC. This matches the IBUFDS/OBUFDS IOSTANDARD in
# rtl/infra/sync_io.v — keep the two in step.
#
# HARDWARE GATE (Batch 2 — Decision D-A2, NOT this package): the pin LOCs below
# are FPGA-internally valid Daisy_IO diff pairs on the clg400 package (so the
# Vivado DRC gate is clean). Whether the trigger reaches the second board via the
# *X-channel 2.0 Click Shield* (shared oscillator, out-of-the-box — the assumed
# default) or via *direct S1/S2 cabling* (which may need a secondary-board HW mod)
# is a Batch-2 hardware-bring-up decision. fpga/drc_gen2.tcl validates FPGA-
# internal legality here; physical routing is validated at Batch-2 bring-up.
#
# Termination: if the IBUFDS input chatters when the daisy link is unplugged, the
# slave-side RX pair may need a pull-down or differential termination —
# DIFF_SSTL18_I has no implicit DIFF_TERM. Verify behaviour before adding one.

set_property PACKAGE_PIN V6  [get_ports {daisy_p_o[0]}] ;  # DAISY_IO0_P  TX0 (trigger)
set_property PACKAGE_PIN W6  [get_ports {daisy_n_o[0]}] ;  # DAISY_IO0_N
set_property PACKAGE_PIN U7  [get_ports {daisy_p_o[1]}] ;  # DAISY_IO1_P  TX1 (reserved)
set_property PACKAGE_PIN V7  [get_ports {daisy_n_o[1]}] ;  # DAISY_IO1_N
set_property PACKAGE_PIN T5  [get_ports {daisy_p_i[0]}] ;  # DAISY_IO2_P  RX0 (trigger)
set_property PACKAGE_PIN U5  [get_ports {daisy_n_i[0]}] ;  # DAISY_IO2_N
set_property PACKAGE_PIN T9  [get_ports {daisy_p_i[1]}] ;  # DAISY_IO3_P  RX1 (reserved)
set_property PACKAGE_PIN U10 [get_ports {daisy_n_i[1]}] ;  # DAISY_IO3_N
set_property IOSTANDARD DIFF_SSTL18_I [get_ports {daisy_p_o[*] daisy_n_o[*] daisy_p_i[*] daisy_n_i[*]}]

# The daisy-IN pairs are asynchronous to the local adc_clk — they're driven by
# the master board's freq_counter.gate_done, in a different (free-running) clock
# domain. Unlike the stock Red Pitaya design, this retarget does NOT create a
# clock on daisy_p_i[1] — no forwarded sample clock is used; both RX pairs are
# treated as async. The 2-FF synchroniser at sync_io.v's input (ASYNC_REG = TRUE)
# handles the clock-domain crossing. The set_false_path below documents that
# intent so Vivado doesn't time the cross-clock path and STA doesn't carry a
# misleading "Slack: inf" line for the daisy inputs.
set_false_path -from [get_ports {daisy_p_i[*]}] -to [all_clocks]
set_false_path -from [get_ports {daisy_n_i[*]}] -to [all_clocks]

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
