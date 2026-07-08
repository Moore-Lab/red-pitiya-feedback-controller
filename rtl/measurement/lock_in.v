`timescale 1ns / 1ps
//
// lock_in.v — I/Q lock-in demodulator measurement block.
//
// Conforms to rtl/measurement/INTERFACE.md (error_count, amplitude, gate_done) so it
// is a drop-in replacement for freq_counter in a control lane. Demodulates the ADC
// against an internal reference NCO at `ref_tuning_word`, accumulates I and Q over the
// gate window, and outputs a magnitude estimate (alpha-max-beta-min) as the error
// signal — suitable for amplitude/COM control (drive the mode amplitude to a setpoint).
//
// Reference cos/sin come from the same 4096x14 sine LUT as dac_sine (sine_lut.mem),
// with cos = sin(phase + 90deg). i_out/q_out are exposed for debug/logging.
//
// Verified by rtl/tb/tb_lock_in.v: an in-band tone yields a large magnitude; an
// out-of-band reference (and a DC input) are strongly rejected.
//
// Refinement left for hardware bring-up: replace the alpha-max-beta-min magnitude with
// a CORDIC sqrt(I^2+Q^2) + atan2 phase if true magnitude/phase accuracy is needed, and
// add an I/Q low-pass (CIC+FIR) ahead of the gate accumulator for narrowband work.
//
module lock_in #(
    parameter integer DATA_WIDTH = 16
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire signed [DATA_WIDTH-1:0] adc_sample,

    input  wire        [31:0]           gate_cycles,     // integration window (shared reg)
    input  wire        [15:0]           threshold,       // unused; kept for interface parity

    input  wire        [31:0]           ref_tuning_word, // reference NCO phase increment

    output reg  signed [31:0]           error_count,     // magnitude estimate (the error signal)
    output reg         [15:0]           amplitude,        // same magnitude, clamped to 16 bits
    output reg                          gate_done,
    // debug / logging
    output reg  signed [31:0]           i_out,
    output reg  signed [31:0]           q_out
);
    // --- reference NCO + sine LUT (cos = sin + 90 deg) ---
    reg  [31:0] phase;
    reg  signed [13:0] lut [0:4095];
    initial $readmemh("sine_lut.mem", lut);
    wire [11:0] idx_sin = phase[31:20];
    wire [11:0] idx_cos = phase[31:20] + 12'd1024;   // +quarter of 4096 = +90 deg
    wire signed [13:0] ref_sin = lut[idx_sin];
    wire signed [13:0] ref_cos = lut[idx_cos];

    // --- gate timer ---
    wire [31:0] gate_len = (gate_cycles == 0) ? 32'd1250000 : gate_cycles;
    reg  [31:0] gate_ctr;

    // --- I/Q accumulators ---
    reg  signed [63:0] acc_i, acc_q;
    wire signed [63:0] prod_i = adc_sample * ref_cos;
    wire signed [63:0] prod_q = adc_sample * ref_sin;

    // --- combinational magnitude of the current accumulators (scaled) ---
    wire signed [63:0] i_scaled = acc_i >>> 16;
    wire signed [63:0] q_scaled = acc_q >>> 16;
    wire        [63:0] ai = i_scaled[63] ? -i_scaled : i_scaled;
    wire        [63:0] aq = q_scaled[63] ? -q_scaled : q_scaled;
    wire        [63:0] mx = (ai > aq) ? ai : aq;
    wire        [63:0] mn = (ai > aq) ? aq : ai;
    wire        [63:0] mag = mx + (mn >> 2);          // alpha-max-beta-min, beta=1/4

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= 32'd0; gate_ctr <= 32'd0;
            acc_i <= 64'sd0; acc_q <= 64'sd0;
            gate_done <= 1'b0; error_count <= 32'sd0; amplitude <= 16'd0;
            i_out <= 32'sd0; q_out <= 32'sd0;
        end else begin
            phase <= phase + ref_tuning_word;
            if (gate_ctr >= gate_len - 1) begin
                gate_ctr    <= 32'd0;
                gate_done   <= 1'b1;
                i_out       <= i_scaled[31:0];
                q_out       <= q_scaled[31:0];
                error_count <= mag[31:0];
                amplitude   <= (mag > 64'd65535) ? 16'hFFFF : mag[15:0];
                acc_i       <= prod_i;    // restart with the current sample
                acc_q       <= prod_q;
            end else begin
                gate_ctr  <= gate_ctr + 1'b1;
                gate_done <= 1'b0;
                acc_i     <= acc_i + prod_i;
                acc_q     <= acc_q + prod_q;
            end
        end
    end

endmodule
