`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// pulse_generator.v  (WP-PULSEGEN, framework I/O library)
//
// Generic, reusable pulse-train generator for any actuator (filament heater
// relay, flash-lamp trigger, gate strobe, ...). It carries NO application
// policy: no charge/filament/flash-lamp specifics and no interlock. Which
// outputs are mutually exclusive is instrument-side (WP-BD-CHARGE); this block
// only shapes a configurable pulse train.
//
// Frozen interface (INTERFACES.md section 2):
//   (clk, rst_n, enable, trigger,
//    period[31:0], width[31:0], amplitude[13:0], count[15:0])
//     -> (pulse_out[13:0], active)
//
// Style mirrors the framework baseline (blinker.v / dac_sine.v): single fabric
// clock domain (native 125-14, no CDC), synchronous logic with an active-low
// asynchronous reset, enable-gated 32-bit counters, and 14-bit DAC-code
// amplitude (INTERFACES section 7).
//
// SEMANTICS (a valid refinement of the frozen interface):
//   * enable=0 -> idle: pulse_out=0, active=0, and ALL internal state
//     (phase counter, pulse counter, run flag) is cleared.
//   * Pulse shape while running: each period is `period` clk cycles. Within a
//     period the output is asserted for the first `width` cycles
//     (active=1, pulse_out=amplitude), then deasserted for the remaining
//     `period-width` cycles (active=0, pulse_out=0).
//       - Well-defined domain is 0 < width <= period.
//       - width >= period  => fully ON for the whole period (the phase counter
//         only ever spans 0..period-1, which is always < width, so every cycle
//         asserts). Documented, deliberate behaviour.
//       - width == 0       => never asserts (a degenerate empty pulse). Also a
//         natural consequence of the same compare; harmless.
//   * count=0  (continuous): while enable=1 the block free-runs a continuous
//     pulse train immediately, with NO trigger required to start. A rising edge
//     on `trigger` restarts the period phase (re-aligns the train).
//   * count=N>0 (burst): the block waits for a rising edge on `trigger`, then
//     emits exactly N full pulse periods and returns to idle until the next
//     rising trigger. Triggers received mid-burst are ignored.
//
// Determinism / glitch-freedom: outputs are true flip-flops (registered from a
// combinational next-state), so pulse_out/active change only on a clock edge.
// Widths and periods are measured in whole fabric clock cycles.
// -----------------------------------------------------------------------------
module pulse_generator (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire        trigger,
    input  wire [31:0] period,
    input  wire [31:0] width,
    input  wire [13:0] amplitude,
    input  wire [15:0] count,
    output reg  [13:0] pulse_out,
    output reg         active
);

    // --- State -------------------------------------------------------------
    reg [31:0] phase_cnt;   // 0 .. period-1 within the current period
    reg [15:0] pulse_cnt;   // full periods emitted so far in the current burst
    reg        running;     // a pulse train is currently being emitted
    reg        trigger_d;   // previous trigger sample, for rising-edge detect

    // Rising-edge detector. trigger_d tracks trigger every cycle (even while
    // disabled) so a level held across the enable transition is NOT mistaken
    // for a fresh edge; only a genuine 0->1 transition arms a burst / restarts.
    wire trig_rise = trigger & ~trigger_d;

    // period_done: this is the last cycle of a period (mirrors blinker.v's
    // `cnt + 1 >= half_period`, which also tolerates live period changes).
    wire period_done = (phase_cnt + 32'd1) >= period;

    // --- Combinational next-state -----------------------------------------
    reg [31:0] next_phase;
    reg [15:0] next_pulse_cnt;
    reg        next_running;

    always @(*) begin
        // hold by default
        next_phase     = phase_cnt;
        next_pulse_cnt = pulse_cnt;
        next_running   = running;

        if (!enable) begin
            // idle: clear everything
            next_phase     = 32'd0;
            next_pulse_cnt = 16'd0;
            next_running   = 1'b0;
        end else if (count == 16'd0) begin
            // ---------- continuous mode ----------
            if (!running) begin
                // free-run starts immediately, no trigger needed
                next_running   = 1'b1;
                next_phase     = 32'd0;
                next_pulse_cnt = 16'd0;
            end else if (trig_rise) begin
                // re-align the train to the trigger
                next_phase = 32'd0;
            end else if (period_done) begin
                next_phase = 32'd0;
            end else begin
                next_phase = phase_cnt + 32'd1;
            end
        end else begin
            // ---------- burst mode (count = N > 0) ----------
            if (!running) begin
                // wait for a rising trigger to arm the burst
                if (trig_rise) begin
                    next_running   = 1'b1;
                    next_phase     = 32'd0;
                    next_pulse_cnt = 16'd0;
                end
            end else begin
                // emitting the burst; mid-burst triggers are ignored
                if (period_done) begin
                    next_phase = 32'd0;
                    if ((pulse_cnt + 16'd1) >= count) begin
                        // Nth period complete -> return to idle
                        next_running   = 1'b0;
                        next_pulse_cnt = 16'd0;
                    end else begin
                        next_pulse_cnt = pulse_cnt + 16'd1;
                    end
                end else begin
                    next_phase = phase_cnt + 32'd1;
                end
            end
        end
    end

    // Output for the NEXT cycle, computed from next-state so the registered
    // output stays exactly aligned with (next_running, next_phase).
    wire next_asserted = next_running && (next_phase < width);

    // --- Sequential --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_cnt <= 32'd0;
            pulse_cnt <= 16'd0;
            running   <= 1'b0;
            trigger_d <= 1'b0;
            active    <= 1'b0;
            pulse_out <= 14'd0;
        end else begin
            trigger_d <= trigger;
            phase_cnt <= next_phase;
            pulse_cnt <= next_pulse_cnt;
            running   <= next_running;
            active    <= next_asserted;
            pulse_out <= next_asserted ? amplitude : 14'd0;
        end
    end

endmodule
