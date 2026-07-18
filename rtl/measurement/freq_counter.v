`timescale 1ns / 1ps

// Zero-crossing frequency counter with Schmitt-trigger hysteresis.
//
// Maintains a 1-bit state (above/below threshold). Transitions:
//   sample > +THRESHOLD → state = 1
//   sample < -THRESHOLD → state = 0
// Counts the 0→1 (rising) transitions of `state` over a configurable gate
// window. This rejects ADC noise-induced multiple crossings.
//
//   f_in = (count_latched * f_clk) / gate_cycles
//
// Timing-conscious construction:
//   - Two input pipeline stages (placement near ADC samples).
//   - Down-counter for the gate (compare against 0, not a 32-bit `>=`).
//   - `gate_cycles - 1` hoisted into a registered target.
//
// Multi-board operation: when `sync_slave_mode = 1` the local gate-window
// counter only serves as a watchdog (it resets the timer when it expires
// but does NOT latch or fire gate_done). The authoritative gate boundary
// is `sync_reset`, transported from the master over the DAISY link via
// sync_io. This makes the slave's gate boundary independent of relative
// crystal drift between the two boards.
//
// ADC_FS vs FABRIC_CLK (WP-ADCFS)
// -------------------------------
// The counter runs in the 125 MHz fabric domain but the ADC sample stream is only
// valid at ADC_FS (62.5 MS/s on 65-16 TI => a valid strobe every OTHER fabric cycle).
// The input pipeline and Schmitt state advance ONLY on the ADC-sample strobe, so
// zero-crossings are detected at the true sample rate (and each detected edge still
// produces exactly one 1-cycle rising pulse). The gate down-counter keeps counting
// fabric cycles, so `gate_cycles` defines the same wall-clock window regardless of
// ADC_FS and the frequency mapping f_in = count * f_fabric / gate_cycles is preserved.
// STROBE_DIV is derived from the build-time ADC_FS / FABRIC_CLK defines:
//     STROBE_DIV = FABRIC_CLK / ADC_FS   (integer, clamped >= 1)
// DEFAULT (ADC_FS == FABRIC_CLK == 125e6) => STROBE_DIV = 1 => a strobe every cycle
// => bit-identical to the original every-cycle path (tb_freq_counter still PASSES).
`ifndef ADC_FS
  `define ADC_FS 125000000
`endif
`ifndef FABRIC_CLK
  `define FABRIC_CLK 125000000
`endif
module freq_counter #(
    // Fabric-cycles per ADC sample. Default 1 (sample every cycle).
    parameter integer STROBE_DIV = ((`FABRIC_CLK / `ADC_FS) < 1)
                                       ? 1 : (`FABRIC_CLK / `ADC_FS)
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire signed [15:0]    sample_in,
    input  wire [31:0]           gate_cycles,
    input  wire signed [15:0]    threshold,     // hysteresis half-band

    // Multi-board trigger sync (tie both to 0 for standalone single-board use)
    input  wire                  sync_reset,        // 1-cycle pulse from sync_io
    input  wire                  sync_slave_mode,   // 1 = sync_reset is authoritative

    output reg  [31:0]           count_latched,
    output reg  [15:0]           amplitude_latched, // peak |sample| over the gate
    output reg                   gate_done
);

// neg_threshold is registered to avoid the negation in the critical path
reg signed [15:0] threshold_reg;
reg signed [15:0] neg_threshold_reg;
always @(posedge clk) begin
    threshold_reg     <= threshold;
    neg_threshold_reg <= -threshold;
end

// --- ADC-sample strobe: high once every STROBE_DIV fabric cycles ---
// For the default STROBE_DIV==1 the compare is (0 >= 0) so stb_cnt stays 0 and
// adc_stb is high every cycle (bit-identical to the original path).
reg  [15:0] stb_cnt;
wire        adc_stb = (stb_cnt == 16'd0);
always @(posedge clk) begin
    if (!rst_n) stb_cnt <= 16'd0;
    else        stb_cnt <= (stb_cnt >= STROBE_DIV - 1) ? 16'd0 : stb_cnt + 16'd1;
end

// --- Input pipeline + Schmitt-trigger state machine ---
// The pipeline advances only on the ADC-sample strobe; on non-strobe cycles the
// rising-edge flag is forced low so each detected crossing yields exactly one
// 1-cycle pulse (crossing_cnt below accumulates it once).
reg signed [15:0] sample_reg;
reg               state, state_prev;
reg               rising_edge_reg;

always @(posedge clk) begin
    if (!rst_n) begin
        sample_reg      <= 16'sd0;
        state           <= 1'b0;
        state_prev      <= 1'b0;
        rising_edge_reg <= 1'b0;
    end else if (adc_stb) begin
        sample_reg <= sample_in;

        if      (sample_reg > threshold_reg)     state <= 1'b1;
        else if (sample_reg < neg_threshold_reg) state <= 1'b0;
        // else: hold

        state_prev      <= state;
        rising_edge_reg <= state && !state_prev;
    end else begin
        rising_edge_reg <= 1'b0;   // no fresh sample => no new edge this cycle
    end
end

// --- Pre-compute and register the down-counter reload value ---
reg [31:0] gate_target;
always @(posedge clk) gate_target <= gate_cycles - 32'd1;

// --- Gate downcounter declarations ---
reg [31:0] down_cnt;
reg [31:0] crossing_cnt;
reg        armed;
wire at_end = (down_cnt == 32'd0);

// --- Mode-dependent latch and timer-reset triggers ---
// In slave mode:
//   - at_end only resets the timer (down_cnt). NO latch, NO gate_done.
//     Acts as a watchdog: keeps down_cnt from underflowing if sync is lost.
//     crossing_cnt continues accumulating across at_end events so that
//     count_latched at the next sync_reset is the count over the actual
//     master-driven gate window.
//   - sync_reset is the authoritative latch + gate_done.
//
// In standalone / master mode:
//   - at_end is the only latch trigger.
//   - sync_reset is gated off in sync_io anyway (reg27 = 0 or master-only).
//   - sync_slave_mode = 0 keeps the original single-board semantics exactly.
wire latch_trigger = sync_reset | (at_end & ~sync_slave_mode);
wire timer_reset   = at_end | sync_reset;

// --- Peak |sample| tracker over the gate window ---
wire signed [15:0] sample_abs_neg = -sample_reg;
wire [15:0]        sample_abs     = (sample_reg[15]) ? sample_abs_neg[15:0]
                                                     : sample_reg[15:0];
reg  [15:0] peak_abs;
always @(posedge clk) begin
    if (!rst_n)               peak_abs <= 16'd0;
    else if (latch_trigger)   peak_abs <= 16'd0;     // reset only when we publish a gate
    else if (sample_abs > peak_abs) peak_abs <= sample_abs;
end

always @(posedge clk) begin
    if (!rst_n) begin
        down_cnt          <= 32'd0;
        crossing_cnt      <= 32'd0;
        count_latched     <= 32'd0;
        amplitude_latched <= 16'd0;
        gate_done         <= 1'b0;
        armed             <= 1'b0;
    end else if (latch_trigger) begin
        // Publish the just-completed gate.
        if (armed) begin
            count_latched     <= crossing_cnt + (rising_edge_reg ? 32'd1 : 32'd0);
            amplitude_latched <= peak_abs;
            gate_done         <= 1'b1;
        end else begin
            gate_done         <= 1'b0;
        end
        crossing_cnt <= 32'd0;
        down_cnt     <= gate_target;
        armed        <= 1'b1;
    end else if (timer_reset) begin
        // Slave-mode watchdog: at_end reloads the timer without latching.
        // crossing_cnt keeps accumulating across this; the next sync_reset
        // will publish the full master-gate-window count.
        down_cnt  <= gate_target;
        gate_done <= 1'b0;
    end else begin
        down_cnt     <= down_cnt - 32'd1;
        crossing_cnt <= crossing_cnt + (rising_edge_reg ? 32'd1 : 32'd0);
        gate_done    <= 1'b0;
    end
end

endmodule
