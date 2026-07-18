`timescale 1ns / 1ps

// Red Pitaya STEMlab ADC interface (LTC2145 on 125-14; LTC2185 on 65-16 TI).
//
// The IBUFDS for the LVDS clock pair lives in the block design (as a Utility
// Buffer IP). This module receives the already-buffered single-ended clock,
// registers the two data buses, and flips the MSB to land in two's complement.
//
// (Per Pavel Demin's red-pitiya-notes, the LTC2145 output is offset binary on
// the ADC pins; the FPGA-side bit reversal is a single MSB invert.)
//
// ADC_FS vs FABRIC_CLK (WP-ADCFS)
// -------------------------------
// The fabric/DAC clock is 125 MHz. On a 65-16 TI board the ADC delivers a new
// sample only every OTHER fabric cycle (62.5 MS/s), i.e. a sample-valid strobe
// rather than a fresh sample on every clock. This module derives that strobe
// from the build-time ADC_FS / FABRIC_CLK defines:
//
//     STROBE_DIV = FABRIC_CLK / ADC_FS      (integer, clamped >= 1)
//
// and:
//   * captures a fresh ADC word only on the strobe (holding it between strobes),
//   * emits `adc_valid` coincident with each freshly-captured word.
//
// DEFAULT (ADC_FS == FABRIC_CLK == 125e6) => STROBE_DIV = 1 => a strobe every
// cycle => capture every cycle => bit-identical to the original always-on path,
// with `adc_valid` tied high. Downstream measurement/DSP blocks consume the
// strobe (they carry the same parameterization) so the whole datapath runs at
// the true ADC sample rate without a second clock domain.

`ifndef ADC_FS
  `define ADC_FS 125000000
`endif
`ifndef FABRIC_CLK
  `define FABRIC_CLK 125000000
`endif

module adc_interface #(
    // Fabric-cycles per ADC sample. Default 1 (a sample every fabric cycle).
    // Derived from the ADC_FS / FABRIC_CLK build defines; override per-build.
    parameter integer STROBE_DIV = ((`FABRIC_CLK / `ADC_FS) < 1)
                                       ? 1 : (`FABRIC_CLK / `ADC_FS)
)(
    input  wire        clk,        // 125 MHz fabric clock (from IBUFDS on adc_clk_p/n)
    input  wire [13:0] adc_dat_a,
    input  wire [13:0] adc_dat_b,

    output reg signed [13:0] adc_a,
    output reg signed [13:0] adc_b,
    output reg               adc_valid  // 1-cycle strobe: adc_a/adc_b freshly captured
);

// -------------------------------------------------------------------------
// ADC-sample strobe: high once every STROBE_DIV fabric cycles. For the default
// STROBE_DIV==1 the compare is (0 >= 0) so stb_cnt stays 0 and adc_stb is high
// every cycle (bit-identical to the original every-cycle capture).
// -------------------------------------------------------------------------
reg  [15:0] stb_cnt = 16'd0;
wire        adc_stb = (stb_cnt == 16'd0);
always @(posedge clk)
    stb_cnt <= (stb_cnt >= STROBE_DIV - 1) ? 16'd0 : stb_cnt + 16'd1;

always @(posedge clk) begin
    if (adc_stb) begin
        adc_a <= {~adc_dat_a[13], adc_dat_a[12:0]};
        adc_b <= {~adc_dat_b[13], adc_dat_b[12:0]};
    end
    adc_valid <= adc_stb;
end

endmodule
