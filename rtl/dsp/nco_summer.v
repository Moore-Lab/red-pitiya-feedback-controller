`timescale 1ns / 1ps

// Combines a static "base" NCO tuning word (set from AXI) with a signed PID
// correction. Output is saturated to the 32-bit unsigned tuning_word range.
//
//   actual_tw = clamp_unsigned(base_tw + (pid_correction <<< shift_left))
//
// `shift_left` lets the user calibrate the PID gain → tuning_word conversion
// to the freq counter's current gate width. For a 10 ms gate, one count of
// freq counter error ≈ 100 Hz ≈ 4096 tuning-word units, so shift_left ≈ 12.
//
// PIPELINED 2026-06-19: previously combinational; the barrel-shift + 64-bit
// add + saturate chain put 64-bit adder routing under timing pressure
// (placement-dominated path at 8.006 ns). Two register stages now:
//   Stage 1: barrel-shift and base extension (registered).
//   Stage 2: 64-bit add + saturate (registered into actual_tw).
// Total latency from inputs to actual_tw: 2 clocks. At the PID's ~100 Hz
// update rate this is invisible (1.25M clocks between updates).
module nco_summer (
    input  wire                clk,
    input  wire                rst_n,
    input  wire [31:0]         base_tw,
    input  wire signed [31:0]  pid_correction,
    input  wire [4:0]          shift_left,        // 0..31

    output reg  [31:0]         actual_tw
);

// Stage 1: barrel shift on PID correction (registered)
reg signed [63:0] scaled_s1;
reg signed [63:0] base_ext_s1;
always @(posedge clk) begin
    if (!rst_n) begin
        scaled_s1   <= 64'sd0;
        base_ext_s1 <= 64'sd0;
    end else begin
        scaled_s1   <= $signed({{32{pid_correction[31]}}, pid_correction}) <<< shift_left;
        base_ext_s1 <= $signed({32'd0, base_tw});
    end
end

// Stage 2: 64-bit add + saturate (registered)
wire signed [63:0] sum_s2 = base_ext_s1 + scaled_s1;
always @(posedge clk) begin
    if (!rst_n) begin
        actual_tw <= 32'd0;
    end else begin
        if      (sum_s2 < 0)                      actual_tw <= 32'd0;
        else if (sum_s2 > 64'sd4294967295)        actual_tw <= 32'hFFFFFFFF;
        else                                       actual_tw <= sum_s2[31:0];
    end
end

endmodule
