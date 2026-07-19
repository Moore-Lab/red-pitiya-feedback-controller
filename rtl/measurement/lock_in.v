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
// ADC_FS vs FABRIC_CLK (WP-ADCFS)
// -------------------------------
// The demodulator runs in the 125 MHz fabric domain but the ADC sample stream is
// only valid at ADC_FS (62.5 MS/s on 65-16 TI => a valid strobe every OTHER fabric
// cycle). The reference NCO advances and the I/Q accumulators integrate ONLY on the
// ADC-sample strobe, so the demod is correct at the true sample rate. The gate window
// (`gate_cycles`) is still counted in fabric cycles, i.e. it defines the same wall-clock
// integration window regardless of ADC_FS; gate_done remains the measurement->control
// handoff strobe. STROBE_DIV is derived from the build-time ADC_FS / FABRIC_CLK defines:
//     STROBE_DIV = FABRIC_CLK / ADC_FS   (integer, clamped >= 1)
// DEFAULT (ADC_FS == FABRIC_CLK == 125e6) => STROBE_DIV = 1 => a strobe every cycle =>
// bit-identical to the original every-cycle accumulator (tb_lock_in still PASSES).
//
`ifndef ADC_FS
  `define ADC_FS 125000000
`endif
`ifndef FABRIC_CLK
  `define FABRIC_CLK 125000000
`endif
module lock_in #(
    parameter integer DATA_WIDTH = 16,
    // Fabric-cycles per ADC sample. Default 1 (accumulate every cycle).
    parameter integer STROBE_DIV = ((`FABRIC_CLK / `ADC_FS) < 1)
                                       ? 1 : (`FABRIC_CLK / `ADC_FS)
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire signed [DATA_WIDTH-1:0] adc_sample,

    input  wire        [31:0]           gate_cycles,     // integration window (shared reg)
    input  wire        [15:0]           threshold,       // unused; kept for interface parity

    input  wire        [31:0]           ref_tuning_word, // reference NCO phase increment

    // multi-board trigger sync (from sync_io.v / DAISY-SATA). Both 0 = standalone.
    input  wire                         sync_reset,      // 1-cycle: latch + restart the gate now
    input  wire                         sync_slave_mode, // 1: gate is driven by sync_reset, not the local timer

    output reg  signed [31:0]           error_count,     // magnitude estimate (the error signal)
    output reg         [15:0]           amplitude,        // same magnitude, clamped to 16 bits
    output reg                          gate_done,
    // debug / logging
    output reg  signed [31:0]           i_out,
    output reg  signed [31:0]           q_out
);
    // --- ADC-sample strobe: high once every STROBE_DIV fabric cycles ---
    // For the default STROBE_DIV==1 the compare is (0 >= 0) so stb_cnt stays 0 and
    // adc_stb is high every cycle (bit-identical to the original path).
    reg  [15:0] stb_cnt;
    wire        adc_stb = (stb_cnt == 16'd0);

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

    // --- demod MAC pipeline: phase->LUT->multiply->accumulate is too long for one 125 MHz
    //     cycle at STROBE_DIV=1 (DSP48 + 64-bit add + LUT muxing ~12 ns). Split it: stage 1
    //     registers the LUT references and the aligned adc sample, stage 2 registers the
    //     products, and the accumulator adds the registered products. The strobe/latch
    //     control is delayed by the same 2 cycles (stb_d2/latch_d2) so integration stays
    //     EXACT (no boundary sample lost) — the demod is just time-shifted 2 cycles (a
    //     constant reference-phase offset absorbed by lock-in phase calibration). See
    //     WP-LOCKIN-TIMING.
    reg  signed [13:0]           ref_cos_r, ref_sin_r;   // stage 1: registered LUT reference
    reg  signed [DATA_WIDTH-1:0] adc_r;                  // stage 1: adc aligned to the refs
    reg  signed [63:0]           prod_i_r, prod_q_r;     // stage 2: registered products
    reg  [1:0]                   stb_pipe, latch_pipe;   // adc_stb / latch_now delayed 2 cycles
    wire                         stb_d2   = stb_pipe[1];
    wire                         latch_d2 = latch_pipe[1];

    // --- scaled accumulators (feed i_out/q_out and the magnitude pipeline) ---
    wire signed [63:0] i_scaled = acc_i >>> 16;
    wire signed [63:0] q_scaled = acc_q >>> 16;

    // --- magnitude pipeline (alpha-max-beta-min), REGISTERED across 3 stages so the
    //     acc -> amplitude path closes 125 MHz timing at STROBE_DIV=1 (a valid sample
    //     every fabric cycle). The old single-cycle 64-bit abs->max/min->add chain was
    //     ~13 ns (32-deep CARRY4) and failed WNS on the first real bitstream. The
    //     pipeline free-runs off the live accumulators; error_count/amplitude latch
    //     mag_p at the gate boundary, so the magnitude carries ~3 samples of extra
    //     latency (negligible over a multi-thousand-sample gate) while i_out/q_out stay
    //     exact. Alpha-max-beta-min value is unchanged. See WP-LOCKIN-TIMING.
    wire        [63:0] ai_c = i_scaled[63] ? -i_scaled : i_scaled;
    wire        [63:0] aq_c = q_scaled[63] ? -q_scaled : q_scaled;
    reg         [63:0] ai_p, aq_p;   // stage 1: |I|, |Q|
    reg         [63:0] mx_p, mn_p;   // stage 2: max, min
    reg         [63:0] mag_p;        // stage 3: max + min/4  (the pipelined magnitude)

    // In slave mode the master's synchronised pulse (sync_reset) is the authoritative
    // gate boundary; the local timer free-runs only as a watchdog and never latches.
    wire local_wrap = (gate_ctr >= gate_len - 1);
    wire latch_now  = sync_slave_mode ? sync_reset : local_wrap;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stb_cnt <= 16'd0;
            phase <= 32'd0; gate_ctr <= 32'd0;
            acc_i <= 64'sd0; acc_q <= 64'sd0;
            ref_cos_r <= 14'sd0; ref_sin_r <= 14'sd0; adc_r <= {DATA_WIDTH{1'b0}};
            prod_i_r <= 64'sd0; prod_q_r <= 64'sd0; stb_pipe <= 2'd0; latch_pipe <= 2'd0;
            ai_p <= 64'd0; aq_p <= 64'd0; mx_p <= 64'd0; mn_p <= 64'd0; mag_p <= 64'd0;
            gate_done <= 1'b0; error_count <= 32'sd0; amplitude <= 16'd0;
            i_out <= 32'sd0; q_out <= 32'sd0;
        end else begin
            // free-running ADC-sample strobe divider
            stb_cnt <= (stb_cnt >= STROBE_DIV - 1) ? 16'd0 : stb_cnt + 16'd1;

            // magnitude pipeline — tracks the live accumulators every fabric cycle so
            // the wide abs/compare/add is split across registers (timing closure).
            ai_p  <= ai_c;
            aq_p  <= aq_c;
            mx_p  <= (ai_p > aq_p) ? ai_p : aq_p;
            mn_p  <= (ai_p > aq_p) ? aq_p : ai_p;
            mag_p <= mx_p + (mn_p >> 2);

            // reference NCO advances one step per ADC sample, not per fabric cycle
            if (adc_stb)
                phase <= phase + ref_tuning_word;

            // demod MAC pipeline: stage 1 registers the LUT refs + the aligned adc sample;
            // stage 2 registers the products. Control (stb/latch) is delayed the same 2
            // cycles below so the gated accumulation stays exact.
            ref_cos_r  <= ref_cos;
            ref_sin_r  <= ref_sin;
            adc_r      <= adc_sample;
            prod_i_r   <= adc_r * ref_cos_r;
            prod_q_r   <= adc_r * ref_sin_r;
            stb_pipe   <= {stb_pipe[0],   adc_stb};
            latch_pipe <= {latch_pipe[0], latch_now};

            // gate counter runs in the fabric domain (fixed wall-clock window),
            // independent of the ADC strobe
            if (sync_slave_mode)
                gate_ctr <= sync_reset ? 32'd0 : gate_ctr + 1'b1;   // watchdog only
            else
                gate_ctr <= local_wrap ? 32'd0 : gate_ctr + 1'b1;

            if (latch_d2) begin
                gate_done   <= 1'b1;
                i_out       <= i_scaled[31:0];
                q_out       <= q_scaled[31:0];
                error_count <= mag_p[31:0];
                amplitude   <= (mag_p > 64'd65535) ? 16'hFFFF : mag_p[15:0];
                // restart the accumulator: seed with this (pipelined) sample's product if
                // the gate boundary coincides with a valid ADC sample, else start clean
                acc_i       <= stb_d2 ? prod_i_r : 64'sd0;
                acc_q       <= stb_d2 ? prod_q_r : 64'sd0;
            end else begin
                gate_done <= 1'b0;
                if (stb_d2) begin
                    acc_i <= acc_i + prod_i_r;   // integrate only on (pipelined) ADC samples
                    acc_q <= acc_q + prod_q_r;
                end
            end
        end
    end

endmodule
