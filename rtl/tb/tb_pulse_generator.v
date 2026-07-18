`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// tb_pulse_generator.v  (WP-PULSEGEN)
//
// Self-checking testbench for rtl/io/pulse_generator.v. Style mirrors
// tb_blinker.v / tb_dac_sine.v: 8 ns tb clock (models 125 MHz fabric),
// active-low reset held for 4 cycles, VCD dump, watchdog.
//
// Every check FAILS LOUDLY: on any mismatch it prints an explicit "FAIL: ..."
// line AND calls $fatal(1, ...) so vvp exits non-zero. Each passing check
// prints "PASS: ...", and a final "ALL TESTS PASSED" precedes $finish.
//
// Coverage (task letters match the WP-PULSEGEN acceptance list):
//   (a) enable=0 -> pulse_out stays 0, active stays 0 (triggers ignored).
//   (b) burst count=N: exactly N pulses on a trigger, then idle; a second
//       trigger produces another N.
//   (c) continuous count=0: free-runs while enabled (no trigger); idles when
//       enable drops.
//   (d) width & period timing: asserted-cycles == width and pulse spacing
//       == period for a representative setting.
//   (e) active is high exactly during the asserted window and tracks
//       pulse_out != 0 (checked every cycle for the whole run).
//   (f) count=1 minimal burst: one trigger => EXACTLY one pulse (width
//       asserted cycles), then idle; a second trigger => exactly one more.
//   (g) width >= period fully-ON: with width==period AND width>period the
//       output asserts EVERY cycle (active stays 1, no deassert gap, no
//       glitch at the period wrap).
//   (h) trigger held HIGH across the enable 0->1 transition is NOT a fresh
//       edge: no burst starts; a subsequent genuine 0->1 edge emits N.
//   (i) mid-burst stray trigger is ignored: an extra rising edge during an
//       active burst neither restarts nor extends it (still exactly N).
//
// Run (from the repo root):
//   iverilog -o pg.out rtl/tb/tb_pulse_generator.v rtl/io/pulse_generator.v
//   vvp pg.out
//
// Sampling convention: reads after @(posedge clk) return the value held during
// the cycle just ended (the DUT's non-blocking updates land after the TB read),
// so consecutive samples give the exact per-cycle output sequence. Absolute
// alignment is offset by one edge, which does not affect edge counts, run
// lengths, or edge-to-edge spacing.
// -----------------------------------------------------------------------------
module tb_pulse_generator;

    parameter [13:0] AMP = 14'h1FFF;   // 8191 — a fixed, nonzero DAC code

    reg         clk       = 1'b0;
    reg         rst_n     = 1'b0;
    reg         enable    = 1'b0;
    reg         trigger   = 1'b0;
    reg  [31:0] period    = 32'd0;
    reg  [31:0] width     = 32'd0;
    reg  [13:0] amplitude = AMP;       // held constant for the whole run
    reg  [15:0] count     = 16'd0;
    wire [13:0] pulse_out;
    wire        active;

    pulse_generator dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .enable    (enable),
        .trigger   (trigger),
        .period    (period),
        .width     (width),
        .amplitude (amplitude),
        .count     (count),
        .pulse_out (pulse_out),
        .active    (active)
    );

    // 8 ns clock (models the 125 MHz fabric clock)
    always #4 clk = ~clk;

    // ------------------------------------------------------------------
    // (e) Continuous invariant, checked every cycle after reset:
    //     pulse_out == (active ? amplitude : 0)  AND  active == (pulse_out!=0).
    //     amplitude is a fixed nonzero code, so the two are equivalent, and
    //     this pins "active is high exactly when pulse_out is driven".
    // ------------------------------------------------------------------
    integer inv_cycles = 0;
    always @(posedge clk) begin
        if (rst_n) begin
            if (pulse_out !== (active ? AMP : 14'd0)) begin
                $display("FAIL: (e) pulse_out=%0d but active=%b (expected %0d)",
                         pulse_out, active, (active ? AMP : 14'd0));
                $fatal(1, "invariant: pulse_out must equal active?amplitude:0");
            end
            if (active !== (pulse_out != 14'd0)) begin
                $display("FAIL: (e) active=%b does not track pulse_out!=0 (pulse_out=%0d)",
                         active, pulse_out);
                $fatal(1, "invariant: active must track pulse_out!=0");
            end
            inv_cycles = inv_cycles + 1;
        end
    end

    // Loop / measurement scratch
    integer i;
    integer edges;
    integer run1;
    integer edge1;
    integer edge2;
    integer tail_bad;
    reg     prev;

    // Fire one clean rising edge on trigger. Stimulus is driven 1 ns AFTER a
    // posedge (between clock edges) so trigger transitions never share a delta
    // with the sampling edge: at the following posedge the DUT sees trigger=1
    // while trigger_d is still 0, i.e. a genuine 0->1 edge. Callers place idle
    // (trigger=0) cycles between fires so each fire is a fresh transition.
    task fire_trigger;
        begin
            @(posedge clk);
            #1 trigger = 1'b1;   // rise off-edge; stable before next posedge
            @(posedge clk);      // DUT samples the rising edge here -> arm
            #1 trigger = 1'b0;   // release off-edge
        end
    endtask

    initial begin
        $dumpfile("tb_pulse_generator.vcd");
        $dumpvars(0, tb_pulse_generator);

        // Hold reset for 4 cycles
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // ============================================================
        // (a) enable=0 -> output idle regardless of trigger / config
        // ============================================================
        enable = 1'b0;
        period = 32'd10;
        width  = 32'd3;
        count  = 16'd5;
        repeat (3) fire_trigger;   // bang on trigger while disabled
        tail_bad = 0;
        for (i = 0; i < 40; i = i + 1) begin
            @(posedge clk);
            if (active !== 1'b0 || pulse_out !== 14'd0) tail_bad = tail_bad + 1;
        end
        if (tail_bad != 0) begin
            $display("FAIL: (a) output not idle with enable=0 (%0d bad cycles)", tail_bad);
            $fatal(1, "enable=0 must force idle");
        end
        $display("PASS: (a) enable=0 holds pulse_out=0, active=0 (triggers ignored)");

        // ============================================================
        // (b) burst count=N: exactly N pulses per trigger, then idle;
        //     repeatable on the next trigger.
        // ============================================================
        enable = 1'b0; @(posedge clk); @(posedge clk);   // clean idle
        period = 32'd10;
        width  = 32'd3;
        count  = 16'd3;
        enable = 1'b1;

        // must stay idle until a trigger arrives (no free-run in burst mode)
        tail_bad = 0;
        for (i = 0; i < 15; i = i + 1) begin
            @(posedge clk);
            if (active !== 1'b0) tail_bad = tail_bad + 1;
        end
        if (tail_bad != 0) begin
            $display("FAIL: (b) burst ran before any trigger (%0d active cycles)", tail_bad);
            $fatal(1, "burst mode must wait for a trigger");
        end

        // ---- first trigger: expect exactly 3 pulses ----
        fire_trigger;
        edges = 0; prev = 1'b0;
        for (i = 0; i < 60; i = i + 1) begin
            @(posedge clk);
            if (!prev && active) edges = edges + 1;
            prev = active;
        end
        if (edges != 3) begin
            $display("FAIL: (b) first burst produced %0d pulses, expected 3", edges);
            $fatal(1, "burst pulse count wrong");
        end
        // and must have returned to idle (window above outlasts the burst)
        tail_bad = 0;
        for (i = 0; i < 15; i = i + 1) begin
            @(posedge clk);
            if (active !== 1'b0) tail_bad = tail_bad + 1;
        end
        if (tail_bad != 0) begin
            $display("FAIL: (b) not idle after first burst (%0d active cycles)", tail_bad);
            $fatal(1, "burst must return to idle");
        end

        // ---- second trigger: another exactly-3 pulses ----
        fire_trigger;
        edges = 0; prev = 1'b0;
        for (i = 0; i < 60; i = i + 1) begin
            @(posedge clk);
            if (!prev && active) edges = edges + 1;
            prev = active;
        end
        if (edges != 3) begin
            $display("FAIL: (b) second burst produced %0d pulses, expected 3", edges);
            $fatal(1, "second burst pulse count wrong");
        end
        $display("PASS: (b) burst emits exactly N=3 pulses per trigger, then idle (repeatable)");

        // ============================================================
        // (c) continuous count=0: free-runs while enabled (no trigger),
        //     returns to idle when enable drops.
        // ============================================================
        enable = 1'b0; @(posedge clk); @(posedge clk);
        period  = 32'd8;
        width   = 32'd2;
        count   = 16'd0;
        trigger = 1'b0;              // never trigger: prove self-start
        enable  = 1'b1;
        edges = 0; prev = 1'b0;
        for (i = 0; i < 40; i = i + 1) begin
            @(posedge clk);
            if (!prev && active) edges = edges + 1;
            prev = active;
        end
        if (edges < 4) begin
            $display("FAIL: (c) continuous mode produced only %0d pulses with no trigger", edges);
            $fatal(1, "continuous mode must free-run while enabled");
        end
        // drop enable -> idle and stay idle
        enable = 1'b0;
        @(posedge clk); @(posedge clk);
        tail_bad = 0;
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk);
            if (active !== 1'b0 || pulse_out !== 14'd0) tail_bad = tail_bad + 1;
        end
        if (tail_bad != 0) begin
            $display("FAIL: (c) not idle after enable dropped (%0d bad cycles)", tail_bad);
            $fatal(1, "dropping enable must force idle");
        end
        $display("PASS: (c) continuous mode free-runs (%0d pulses, no trigger), idles when disabled", edges);

        // ============================================================
        // (d) width/period timing: asserted-cycles == width and the
        //     spacing between successive pulses == period.
        // ============================================================
        enable = 1'b0; @(posedge clk); @(posedge clk);
        period  = 32'd12;
        width   = 32'd5;
        count   = 16'd0;
        trigger = 1'b0;
        enable  = 1'b1;
        prev = 1'b0; edge1 = -1; edge2 = -1; run1 = 0;
        for (i = 0; i < 48; i = i + 1) begin
            @(posedge clk);
            if (!prev && active) begin
                if (edge1 < 0)      edge1 = i;
                else if (edge2 < 0) edge2 = i;
            end
            // count contiguous high cycles of the first pulse (one high run/period)
            if (edge1 >= 0 && edge2 < 0 && active) run1 = run1 + 1;
            prev = active;
        end
        if (edge1 < 0 || edge2 < 0) begin
            $display("FAIL: (d) fewer than two pulses observed (edge1=%0d edge2=%0d)", edge1, edge2);
            $fatal(1, "timing scan found too few pulses");
        end
        if (run1 != 5) begin
            $display("FAIL: (d) asserted-cycles = %0d, expected width = 5", run1);
            $fatal(1, "width mismatch");
        end
        if ((edge2 - edge1) != 12) begin
            $display("FAIL: (d) pulse spacing = %0d cycles, expected period = 12", (edge2 - edge1));
            $fatal(1, "period mismatch");
        end
        $display("PASS: (d) asserted-cycles==width(5) and pulse spacing==period(12)");

        // ============================================================
        // (f) count=1 minimal burst: one trigger -> EXACTLY one pulse
        //     (width asserted cycles), then idle; a second trigger ->
        //     exactly one more.
        // ============================================================
        enable = 1'b0; @(posedge clk); @(posedge clk);   // clean idle
        period  = 32'd10;
        width   = 32'd3;
        count   = 16'd1;
        trigger = 1'b0;
        enable  = 1'b1;
        @(posedge clk); @(posedge clk);   // must stay idle until triggered

        // ---- first trigger: exactly one pulse of width cycles ----
        fire_trigger;
        edges = 0; prev = 1'b0; run1 = 0;
        for (i = 0; i < 40; i = i + 1) begin
            @(posedge clk);
            if (!prev && active) edges = edges + 1;
            if (active) run1 = run1 + 1;   // total asserted cycles in the burst
            prev = active;
        end
        if (edges != 1) begin
            $display("FAIL: (f) count=1 first trigger produced %0d pulses, expected 1", edges);
            $fatal(1, "count=1 must emit exactly one pulse");
        end
        if (run1 != 3) begin
            $display("FAIL: (f) count=1 pulse asserted %0d cycles, expected width=3", run1);
            $fatal(1, "count=1 single-pulse width wrong");
        end

        // ---- second trigger: exactly one more pulse ----
        fire_trigger;
        edges = 0; prev = 1'b0;
        for (i = 0; i < 40; i = i + 1) begin
            @(posedge clk);
            if (!prev && active) edges = edges + 1;
            prev = active;
        end
        if (edges != 1) begin
            $display("FAIL: (f) count=1 second trigger produced %0d pulses, expected 1", edges);
            $fatal(1, "count=1 second trigger must emit exactly one pulse");
        end
        $display("PASS: (f) count=1 emits exactly one pulse per trigger (width=3), repeatable");

        // ============================================================
        // (g) width >= period => fully ON: the output asserts EVERY cycle
        //     of every period (active stays 1, no deassert gap, no glitch
        //     at the period wrap). Tested for width==period and width>period
        //     using continuous mode so the train free-runs across many wraps.
        // ============================================================
        // width == period
        enable = 1'b0; @(posedge clk); @(posedge clk);
        period  = 32'd8;
        width   = 32'd8;
        count   = 16'd0;
        trigger = 1'b0;
        enable  = 1'b1;
        repeat (4) @(posedge clk);   // let the train start
        tail_bad = 0;
        for (i = 0; i < 40; i = i + 1) begin
            @(posedge clk);          // window spans ~5 period wraps
            if (active !== 1'b1 || pulse_out !== AMP) tail_bad = tail_bad + 1;
        end
        if (tail_bad != 0) begin
            $display("FAIL: (g) width==period not fully ON (%0d non-asserted cycles)", tail_bad);
            $fatal(1, "width==period must assert every cycle");
        end

        // width > period (behaves identically: fully ON)
        enable = 1'b0; @(posedge clk); @(posedge clk);
        period  = 32'd8;
        width   = 32'd12;
        count   = 16'd0;
        trigger = 1'b0;
        enable  = 1'b1;
        repeat (4) @(posedge clk);
        tail_bad = 0;
        for (i = 0; i < 40; i = i + 1) begin
            @(posedge clk);
            if (active !== 1'b1 || pulse_out !== AMP) tail_bad = tail_bad + 1;
        end
        if (tail_bad != 0) begin
            $display("FAIL: (g) width>period not fully ON (%0d non-asserted cycles)", tail_bad);
            $fatal(1, "width>period must assert every cycle");
        end
        $display("PASS: (g) width>=period asserts every cycle (fully ON, no wrap glitch)");

        // ============================================================
        // (h) trigger held HIGH across the enable 0->1 transition must NOT
        //     be treated as a fresh edge (trigger_d tracks even while
        //     disabled). Burst mode: no burst starts. A subsequent genuine
        //     0->1 edge then emits exactly N.
        // ============================================================
        enable = 1'b0; @(posedge clk); @(posedge clk);   // clean idle, trigger=0
        period = 32'd10;
        width  = 32'd3;
        count  = 16'd4;
        // Raise trigger and hold it high while STILL disabled, letting the
        // DUT's trigger_d catch up to 1 before enable rises.
        @(posedge clk); #1 trigger = 1'b1;
        @(posedge clk);                 // trigger_d <= 1 (enable still 0)
        @(posedge clk);                 // trigger_d stays 1
        // Bring enable high with trigger still held high: trig_rise stays 0.
        #1 enable = 1'b1;
        tail_bad = 0;
        for (i = 0; i < 40; i = i + 1) begin
            @(posedge clk);
            if (active !== 1'b0) tail_bad = tail_bad + 1;
        end
        if (tail_bad != 0) begin
            $display("FAIL: (h) trigger held across enable rise armed a burst (%0d active cycles)", tail_bad);
            $fatal(1, "held-high trigger across enable must not be a fresh edge");
        end
        // Drop trigger, let trigger_d fall, then a genuine new rising edge
        // must arm and emit exactly N pulses.
        #1 trigger = 1'b0;
        @(posedge clk); @(posedge clk);   // trigger_d -> 0
        fire_trigger;
        edges = 0; prev = 1'b0;
        for (i = 0; i < 80; i = i + 1) begin
            @(posedge clk);
            if (!prev && active) edges = edges + 1;
            prev = active;
        end
        if (edges != 4) begin
            $display("FAIL: (h) genuine edge after held trigger produced %0d pulses, expected 4", edges);
            $fatal(1, "post-hold genuine trigger must emit N pulses");
        end
        $display("PASS: (h) held-high trigger across enable arms nothing; a fresh edge emits N=4");

        // ============================================================
        // (i) mid-burst stray trigger is ignored: an extra rising edge
        //     during an active burst neither restarts nor extends it
        //     (still exactly N pulses total).
        // ============================================================
        enable = 1'b0; @(posedge clk); @(posedge clk);
        period  = 32'd10;
        width   = 32'd3;
        count   = 16'd4;
        trigger = 1'b0;
        enable  = 1'b1;
        @(posedge clk); @(posedge clk);   // idle, waiting for trigger
        fire_trigger;                     // start the 4-pulse burst
        edges = 0; prev = 1'b0;
        for (i = 0; i < 80; i = i + 1) begin
            @(posedge clk);
            if (!prev && active) edges = edges + 1;
            prev = active;
            // Inject a one-cycle stray rising edge partway through the burst
            // (~1.5 periods in, well before the 40-cycle burst completes).
            if (i == 15) #1 trigger = 1'b1;
            if (i == 16) #1 trigger = 1'b0;
        end
        if (edges != 4) begin
            $display("FAIL: (i) burst with mid-burst stray trigger produced %0d pulses, expected 4", edges);
            $fatal(1, "mid-burst stray trigger must be ignored (no restart/extension)");
        end
        $display("PASS: (i) mid-burst stray trigger ignored; exactly N=4 pulses total");

        // quiesce
        enable = 1'b0;
        @(posedge clk);

        $display("PASS: (e) invariant pulse_out==(active?amp:0) & active==(pulse_out!=0) held for %0d cycles",
                 inv_cycles);
        $display("ALL TESTS PASSED");
        $finish;
    end

    // Watchdog
    initial begin
        #2000000;
        $display("FAIL: testbench timeout");
        $fatal(1, "timeout");
    end

endmodule
