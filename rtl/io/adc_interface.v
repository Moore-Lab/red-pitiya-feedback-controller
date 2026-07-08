`timescale 1ns / 1ps

// Red Pitaya STEMlab 125-14 ADC interface (LTC2145).
//
// The IBUFDS for the LVDS clock pair lives in the block design (as a Utility
// Buffer IP). This module receives the already-buffered single-ended clock,
// registers the two data buses, and flips the MSB to land in two's complement.
//
// (Per Pavel Demin's red-pitaya-notes, the LTC2145 output is offset binary on
// the ADC pins; the FPGA-side bit reversal is a single MSB invert.)
module adc_interface (
    input  wire        clk,        // 125 MHz fabric clock (from IBUFDS on adc_clk_p/n)
    input  wire [13:0] adc_dat_a,
    input  wire [13:0] adc_dat_b,

    output reg signed [13:0] adc_a,
    output reg signed [13:0] adc_b
);

always @(posedge clk) begin
    adc_a <= {~adc_dat_a[13], adc_dat_a[12:0]};
    adc_b <= {~adc_dat_b[13], adc_dat_b[12:0]};
end

endmodule
