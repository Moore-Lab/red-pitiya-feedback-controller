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

    // Pre-registered comparison constants: period-1 and width-1 are registered once
    // (period/width are quasi-static AXI inputs) so the hot phase_cnt -> {period_done,
    // asserted} paths are pure compares against the registered phase_cnt with NO 32-bit
    // adder in series — the adder+compare chain missed 125 MHz timing on real silicon
    // (board_charge). A period/width change takes effect one cycle later, harmless.
    // See WP-LOCKIN-TIMING.
    reg [31:0] period_m1;   // period - 1  (0 if period == 0)
    reg [31:0] width_m1;    // width  - 1  (0 if width  == 0)
    reg        width_nz;    // width != 0
    // period_done: last cycle of a period.  (phase_cnt+1 >= period) == (phase_cnt >= period-1)
    wire period_done = (phase_cnt >= period_m1);

    // --- Combinational next-state -----------------------------------------
    reg [31:0] next_phase;
    reg [15:0] next_pulse_cnt;
    reg        next_running;
    reg        next_zero;      // 1 iff next_phase == 0, tracked explicitly so the asserted
                               // path needs no adder on phase_cnt (idle holds phase_cnt @ 0)

    always @(*) begin
        // hold by default (idle: phase_cnt is 0 whenever the block is not running)
        next_phase     = phase_cnt;
        next_pulse_cnt = pulse_cnt;
        next_running   = running;
        next_zero      = 1'b1;

        if (!enable) begin
            // idle: clear everything
            next_phase     = 32'd0;
            next_pulse_cnt = 16'd0;
            next_running   = 1'b0;
            next_zero      = 1'b1;
        end else if (count == 16'd0) begin
            // ---------- continuous mode ----------
            if (!running) begin
                // free-run starts immediately, no trigger needed
                next_running   = 1'b1;
                next_phase     = 32'd0;
                next_pulse_cnt = 16'd0;
                next_zero      = 1'b1;
            end else if (trig_rise) begin
                // re-align the train to the trigger
                next_phase = 32'd0;
                next_zero  = 1'b1;
            end else if (period_done) begin
                next_phase = 32'd0;
                next_zero  = 1'b1;
            end else begin
                next_phase = phase_cnt + 32'd1;
                next_zero  = 1'b0;
            end
        end else begin
            // ---------- burst mode (count = N > 0) ----------
            if (!running) begin
                // wait for a rising trigger to arm the burst (else hold, idle @ phase 0)
                if (trig_rise) begin
                    next_running   = 1'b1;
                    next_phase     = 32'd0;
                    next_pulse_cnt = 16'd0;
                    next_zero      = 1'b1;
                end
            end else begin
                // emitting the burst; mid-burst triggers are ignored
                if (period_done) begin
                    next_phase = 32'd0;
                    next_zero  = 1'b1;
                    if ((pulse_cnt + 16'd1) >= count) begin
                        // Nth period complete -> return to idle
                        next_running   = 1'b0;
                        next_pulse_cnt = 16'd0;
                    end else begin
                        next_pulse_cnt = pulse_cnt + 16'd1;
                    end
                end else begin
                    next_phase = phase_cnt + 32'd1;
                    next_zero  = 1'b0;
                end
            end
        end
    end

    // Asserted decision with NO adder on the hot path: when next_phase wraps to 0 the pulse
    // asserts iff width != 0; otherwise (next_phase == phase_cnt+1) it asserts iff
    // phase_cnt+1 < width, i.e. phase_cnt < width-1 == width_m1 — a pure compare on the
    // registered phase_cnt. Exactly equal to the old (next_running && next_phase < width).
    wire phase_lt_w    = (phase_cnt < width_m1);
    wire next_asserted = next_running && (next_zero ? width_nz : phase_lt_w);

    // --- Sequential --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_cnt <= 32'd0;
            pulse_cnt <= 16'd0;
            running   <= 1'b0;
            trigger_d <= 1'b0;
            active    <= 1'b0;
            pulse_out <= 14'd0;
            period_m1 <= 32'd0;
            width_m1  <= 32'd0;
            width_nz  <= 1'b0;
        end else begin
            trigger_d <= trigger;
            // pre-register the comparison constants (quasi-static; settle in 1 cycle)
            period_m1 <= (period == 32'd0) ? 32'd0 : period - 32'd1;
            width_m1  <= (width  == 32'd0) ? 32'd0 : width  - 32'd1;
            width_nz  <= (width != 32'd0);
            phase_cnt <= next_phase;
            pulse_cnt <= next_pulse_cnt;
            running   <= next_running;
            active    <= next_asserted;
            pulse_out <= next_asserted ? amplitude : 14'd0;
        end
    end

endmodule
