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

// IO-FLAVOR SELECTION (65-16 TI serial-LVDS vs 125-14 parallel-CMOS)
// ------------------------------------------------------------------
// This module is the 125-14 parallel-CMOS front end: it registers the two
// parallel ADC buses and converts the on-pin offset-binary to two's-complement
// (a single MSB invert). The 65-16 TI board's serial-LVDS front end is a
// SEPARATE module, rtl/io/adc_deserial_ll.v (IDELAY/ISERDES lane capture ->
// 16-bit word), which already delivers signed samples and shares this module's
// output contract (adc_a, adc_b, adc_valid).
//
// The ADC_SERIAL parameter lets a build select the io flavor's FORMAT behaviour
// through one instantiation:
//   * ADC_SERIAL == 0 (DEFAULT): 125-14 parallel. Offset-binary -> two's-comp
//     via MSB invert. With DW==14 this is BIT-IDENTICAL to the original module.
//   * ADC_SERIAL == 1: fed by adc_deserial_ll (already-signed words); the MSB
//     invert is skipped (pure register + strobe hold). Set DW=16 for the 65-16.
// The DEFAULTS (ADC_SERIAL=0, DW=14) leave the parallel path unchanged.
module adc_interface #(
    // Fabric-cycles per ADC sample. Default 1 (a sample every fabric cycle).
    // Derived from the ADC_FS / FABRIC_CLK build defines; override per-build.
    parameter integer STROBE_DIV = ((`FABRIC_CLK / `ADC_FS) < 1)
                                       ? 1 : (`FABRIC_CLK / `ADC_FS),
    // Sample width. 14 for 125-14 (default), 16 for 65-16 TI serial flavor.
    parameter integer DW = 14,
    // 0 = 125-14 parallel (offset-binary -> two's-comp MSB flip). 1 = serial
    // flavor (input already signed; no flip). Default 0 keeps parallel behavior.
    parameter         ADC_SERIAL = 0
)(
    input  wire            clk,        // 125 MHz fabric clock (from IBUFDS on adc_clk_p/n)
    input  wire [DW-1:0]   adc_dat_a,
    input  wire [DW-1:0]   adc_dat_b,

    output reg signed [DW-1:0] adc_a,
    output reg signed [DW-1:0] adc_b,
    output reg                 adc_valid  // 1-cycle strobe: adc_a/adc_b freshly captured
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
        if (ADC_SERIAL) begin
            // Serial flavor: samples arrive already two's-complement signed
            // (from adc_deserial_ll) — register/hold only, no format flip.
            adc_a <= adc_dat_a;
            adc_b <= adc_dat_b;
        end else begin
            // 125-14 parallel: offset-binary on the pins -> two's-comp (MSB flip).
            // DW==14 reproduces the original {~[13],[12:0]} exactly.
            adc_a <= {~adc_dat_a[DW-1], adc_dat_a[DW-2:0]};
            adc_b <= {~adc_dat_b[DW-1], adc_dat_b[DW-2:0]};
        end
    end
    adc_valid <= adc_stb;
end

endmodule
