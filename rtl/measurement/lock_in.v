`timescale 1ns / 1ps
//
// lock_in.v — STUB measurement block for displacement / COM experiments.
//
// Conforms to rtl/measurement/INTERFACE.md so it is a drop-in replacement for
// freq_counter in a control lane. This is a SKELETON: it demodulates the ADC
// against a reference NCO (I/Q mix) and accumulates over the gate, but the
// magnitude/phase extraction and the compensating low-pass are left as TODOs.
// Do NOT synthesize this into a control loop until it has a testbench that
// verifies the demodulated output against a known injected tone.
//
// Intended completion (first downstream build, e.g. nanosphere):
//   * drive cos/sin from a shared NCO (reuse dac_sine's phase accumulator/LUT)
//     at the mechanical reference frequency (a spec register: lockin_ref_tw);
//   * low-pass filter I and Q (reuse cic_decimator + comp_fir);
//   * magnitude = sqrt(I^2 + Q^2) via CORDIC (amplitude) and atan2 (phase);
//   * output magnitude as error_count for amplitude control, or phase for a PLL.
//
module lock_in #(
    parameter integer DATA_WIDTH = 16
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire signed [DATA_WIDTH-1:0] adc_sample,

    input  wire        [31:0]           gate_cycles,
    input  wire        [15:0]           threshold,      // unused here; kept for interface parity

    // block-specific config: reference oscillator phase increment
    input  wire        [31:0]           ref_tuning_word,
    input  wire signed [DATA_WIDTH-1:0] ref_cos,        // TODO: drive from a shared NCO LUT
    input  wire signed [DATA_WIDTH-1:0] ref_sin,

    output wire signed [31:0]           error_count,
    output wire        [15:0]           amplitude,
    output wire                         gate_done
);

    // --- gate timer ---------------------------------------------------------
    reg [31:0] gate_ctr;
    reg        gate_pulse;
    wire [31:0] gate_len = (gate_cycles == 0) ? 32'd1250000 : gate_cycles;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gate_ctr   <= 0;
            gate_pulse <= 1'b0;
        end else if (gate_ctr >= gate_len - 1) begin
            gate_ctr   <= 0;
            gate_pulse <= 1'b1;
        end else begin
            gate_ctr   <= gate_ctr + 1;
            gate_pulse <= 1'b0;
        end
    end

    // --- I/Q mix + accumulate (STUB: no low-pass yet) -----------------------
    reg signed [47:0] acc_i, acc_q;
    reg signed [47:0] lat_i, lat_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_i <= 0; acc_q <= 0; lat_i <= 0; lat_q <= 0;
        end else begin
            if (gate_pulse) begin
                lat_i <= acc_i; lat_q <= acc_q;
                acc_i <= adc_sample * ref_cos;
                acc_q <= adc_sample * ref_sin;
            end else begin
                acc_i <= acc_i + adc_sample * ref_cos;
                acc_q <= acc_q + adc_sample * ref_sin;
            end
        end
    end

    // TODO: replace this magnitude proxy with a proper CORDIC sqrt(I^2+Q^2).
    // For now expose the in-phase accumulator so the interface is exercised.
    assign error_count = lat_i[47:16];
    assign amplitude   = lat_i[31:16];
    assign gate_done   = gate_pulse;

endmodule
