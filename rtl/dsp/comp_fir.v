`timescale 1ns / 1ps

// 16-tap symmetric FIR with coefficients loaded from `fir_coeffs.mem`.
// Designed to compensate the sinc^4 droop of the cic_decimator (R=25, N=4).
// Coefficients are Q1.15 (signed 16-bit, DC gain ≈ 1).
//
// Stream protocol: in_valid pulses when a new sample is available. The tap
// delay line only advances on in_valid; the multiply-accumulate pipeline runs
// every clock and produces a fresh out_valid one pipeline latency after each
// in_valid pulse.
//
// ADC_FS vs FABRIC_CLK (WP-ADCFS): this block is already rate-agnostic — it
// processes exactly one sample per in_valid pulse. Driven by cic_decimator's
// out_valid (which now pulses at ADC_FS / R), it automatically follows the ADC
// sample rate with no parameter of its own. The droop-compensation coefficients
// depend only on the CIC's R and N (the sinc^4 shape), not on absolute ADC_FS, so
// fir_coeffs.mem does not need regenerating when only ADC_FS changes.
//
// Pipeline: 1 cycle (multiply) + 4 cycles (adder tree) = 5 cycles total.
module comp_fir #(
    parameter NTAPS       = 16,
    parameter DATA_WIDTH  = 16,
    parameter COEFF_WIDTH = 16,
    parameter SCALE_SHIFT = 15      // Q1.15 → output shift
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          in_valid,
    input  wire signed [DATA_WIDTH-1:0]  in_sample,
    output reg  signed [DATA_WIDTH-1:0]  out_sample,
    output reg                           out_valid
);

// --- Tap delay line (advances on in_valid) ---
reg signed [DATA_WIDTH-1:0] taps [0:NTAPS-1];
integer i;

always @(posedge clk) begin
    if (!rst_n) begin
        for (i = 0; i < NTAPS; i = i + 1) taps[i] <= {DATA_WIDTH{1'b0}};
    end else if (in_valid) begin
        taps[0] <= in_sample;
        for (i = 1; i < NTAPS; i = i + 1) taps[i] <= taps[i-1];
    end
end

// --- Coefficient ROM (loaded from .mem at elaboration) ---
reg signed [COEFF_WIDTH-1:0] coeffs [0:NTAPS-1];
initial begin
    `ifdef SIM
        $readmemh("src/fir_coeffs.mem", coeffs);
    `else
        $readmemh("fir_coeffs.mem", coeffs);
    `endif
end

// --- Stage 1: 16 parallel multiplies, registered ---
localparam PROD_W = DATA_WIDTH + COEFF_WIDTH;
reg signed [PROD_W-1:0] products [0:NTAPS-1];
always @(posedge clk) begin
    for (i = 0; i < NTAPS; i = i + 1)
        products[i] <= taps[i] * coeffs[i];
end

// --- Stages 2-5: balanced adder tree, registered at each level ---
// 16 → 8 → 4 → 2 → 1
reg signed [PROD_W+0:0] s8 [0:7];
reg signed [PROD_W+1:0] s4 [0:3];
reg signed [PROD_W+2:0] s2 [0:1];
reg signed [PROD_W+3:0] s1;

always @(posedge clk) begin
    for (i = 0; i < 8; i = i + 1) s8[i] <= products[2*i]   + products[2*i+1];
    for (i = 0; i < 4; i = i + 1) s4[i] <= s8[2*i]         + s8[2*i+1];
    for (i = 0; i < 2; i = i + 1) s2[i] <= s4[2*i]         + s4[2*i+1];
    s1 <= s2[0] + s2[1];
end

// --- Valid pipeline (5 cycles to match the math pipeline depth) ---
reg [4:0] valid_pipe;
always @(posedge clk) begin
    if (!rst_n) valid_pipe <= 5'd0;
    else        valid_pipe <= {valid_pipe[3:0], in_valid};
end

// --- Output: arithmetic shift right by SCALE_SHIFT (Q1.15 → integer) ---
wire signed [PROD_W+3:0] shifted = s1 >>> SCALE_SHIFT;

always @(posedge clk) begin
    if (!rst_n) begin
        out_sample <= {DATA_WIDTH{1'b0}};
        out_valid  <= 1'b0;
    end else if (valid_pipe[4]) begin
        out_sample <= shifted[DATA_WIDTH-1:0];
        out_valid  <= 1'b1;
    end else begin
        out_valid  <= 1'b0;
    end
end

endmodule
