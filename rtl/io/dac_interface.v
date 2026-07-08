`timescale 1ns / 1ps

// Red Pitaya STEMlab 125-14 DAC interface (AD9767-style dual DAC, interleaved bus).
//
// The two DAC channels share a single 14-bit data bus. `dac_sel` indicates
// which channel the next write targets; `dac_wrt` strobes. The forwarded
// `dac_clk` runs at the same rate as the FPGA clock.
//
// At 125 MHz fabric clock with `dac_sel` toggling each cycle:
//   - Each channel gets a new sample every 16 ns → 62.5 MHz per-channel rate.
//   - Plenty for f_DAC up to ~25 MHz (under the AD9767 reconstruction filter).
//
// Format conversion: dac_a_in / dac_b_in are signed two's complement. The DAC
// expects offset binary, so we flip the MSB.
module dac_interface (
    input  wire               clk,        // 125 MHz fabric clock
    input  wire               rst_n,
    input  wire signed [13:0] dac_a_in,
    input  wire signed [13:0] dac_b_in,

    output reg  [13:0]        dac_dat,
    output reg                dac_wrt,
    output reg                dac_sel,
    output wire               dac_clk_o,  // forwarded clock to DAC chip
    output reg                dac_rst
);

reg sel_toggle;

always @(posedge clk) begin
    if (!rst_n) begin
        sel_toggle <= 1'b0;
        dac_dat    <= 14'd0;
        dac_sel    <= 1'b0;
        dac_wrt    <= 1'b0;
        dac_rst    <= 1'b1;
    end else begin
        sel_toggle <= ~sel_toggle;
        if (sel_toggle) begin
            // This cycle sends channel B
            dac_dat <= {~dac_b_in[13], dac_b_in[12:0]};
            dac_sel <= 1'b1;
        end else begin
            // This cycle sends channel A
            dac_dat <= {~dac_a_in[13], dac_a_in[12:0]};
            dac_sel <= 1'b0;
        end
        dac_wrt <= 1'b1;
        dac_rst <= 1'b0;
    end
end

// Forward the fabric clock to the DAC pin with guaranteed low skew
ODDR #(
    .DDR_CLK_EDGE("OPPOSITE_EDGE"),
    .INIT        (1'b0),
    .SRTYPE      ("SYNC")
) dac_clk_oddr (
    .Q  (dac_clk_o),
    .C  (clk),
    .CE (1'b1),
    .D1 (1'b0),
    .D2 (1'b1),
    .R  (1'b0),
    .S  (1'b0)
);

endmodule
