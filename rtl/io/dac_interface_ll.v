`timescale 1ns / 1ps

// dac_interface_ll.v — STEMlab 65-16 TI (Z20_ll) dual DAC interface.
//
// Unlike the 125-14 board's single interleaved DAC bus (rtl/io/dac_interface.v,
// one 14-bit bus + dac_sel), the 65-16 TI board wires the two DAC channels as
// TWO INDEPENDENT 14-bit parallel buses, each with its own write strobe:
//   dac_data_o[13:0] + dac_wrta_o   (channel A)
//   dac_datb_o[13:0] + dac_wrtb_o   (channel B)
// Modeled on the reference red_pitaya_top_ll.sv DAC IO (~lines 264-275):
//   dac_data_o <= {dac_dat_a[13], ~dac_dat_a[...]};    // two's-comp -> offset-binary
//   ODDR oddr_dac_wrta (.D1(1'b0), .D2(1'b1), ...);     // DDR write strobe
//
// FORMAT CONVERSION
// -----------------
// dac_a_in / dac_b_in are signed two's-complement. The Red Pitaya DAC path
// expects (negative-slope) offset binary: KEEP the sign bit and INVERT the
// magnitude bits -> {msb, ~rest}. This matches the reference DAC output
// convention (red_pitaya_top_ll.sv / red_pitaya_top.sv, e.g. dac_dat assembly).
// (The parallel-board dac_interface.v uses the opposite {~msb, rest} slope; the
// slope is a per-board DAC-polarity choice and is confirmed at bring-up.)
//
// WRITE STROBES
// -------------
// Both channels update every fabric cycle, so each write strobe is a continuous
// DDR clock forwarded to the DAC via ODDR (D1=0,D2=1), exactly as the reference.
// The precise strobe edge placement / IOB timing is a Vivado + on-hardware
// concern (GATE); this module provides the RTL + ODDR instances.
module dac_interface_ll (
    input  wire               clk,        // fabric/DAC clock (125 MHz)
    input  wire               clk_wrt,    // strobe clock (may be a phase-shifted clk)
    input  wire               rst_n,
    input  wire signed [13:0] dac_a_in,
    input  wire signed [13:0] dac_b_in,

    output reg  [13:0]        dac_data_o, // channel A parallel data
    output reg  [13:0]        dac_datb_o, // channel B parallel data
    output wire               dac_wrta_o, // channel A write strobe (DDR)
    output wire               dac_wrtb_o, // channel B write strobe (DDR)
    output reg                dac_rst
);

// ---- registered output data + two's-comp -> offset-binary (MSB invert) ----
always @(posedge clk) begin
    if (!rst_n) begin
        dac_data_o <= 14'd0;
        dac_datb_o <= 14'd0;
        dac_rst    <= 1'b1;
    end else begin
        dac_data_o <= {dac_a_in[13], ~dac_a_in[12:0]};
        dac_datb_o <= {dac_b_in[13], ~dac_b_in[12:0]};
        dac_rst    <= 1'b0;
    end
end

// ---- DDR write strobes (continuous clock forwarded to the DAC) ------------
ODDR #(
    .DDR_CLK_EDGE ("SAME_EDGE"),
    .INIT         (1'b0),
    .SRTYPE       ("SYNC")
) oddr_dac_wrta (
    .Q  (dac_wrta_o),
    .C  (clk_wrt),
    .CE (1'b1),
    .D1 (1'b0),
    .D2 (1'b1),
    .R  (1'b0),
    .S  (1'b0)
);

ODDR #(
    .DDR_CLK_EDGE ("SAME_EDGE"),
    .INIT         (1'b0),
    .SRTYPE       ("SYNC")
) oddr_dac_wrtb (
    .Q  (dac_wrtb_o),
    .C  (clk_wrt),
    .CE (1'b1),
    .D1 (1'b0),
    .D2 (1'b1),
    .R  (1'b0),
    .S  (1'b0)
);

endmodule
