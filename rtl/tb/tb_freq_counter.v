`timescale 1ns / 1ps

// Testbench for freq_counter.v
//
// Two modes to test:
//   sync_slave_mode = 0 (standalone / master): at_end is the only latch.
//                                              sync_reset is treated as a latch too
//                                              (so master+sync still produces records;
//                                              and to support the slave-mode tests we
//                                              keep latch_trigger = sync_reset | at_end).
//   sync_slave_mode = 1 (slave):               at_end resets the timer only (watchdog).
//                                              sync_reset is the AUTHORITATIVE latch.
//
// Phases:
//   1.  Standalone 1 MHz check (existing).
//   2.  Slave mode: at_end fires repeatedly without latching; crossing_cnt
//       accumulates across many at_end's; sync_reset finally publishes a
//       count covering the FULL master-gate-window (here simulated by
//       firing sync_reset after several at_ends).
//   3.  Slave mode: sync_reset with no rising edges → gate_done with count=0.
//   4.  Standalone mode: sync_reset still latches (used by master-board path
//       when reg27 = 0 and sync isn't connected — the input is just 0, no risk).

module tb_freq_counter;

    reg               clk             = 0;
    reg               rst_n           = 0;
    reg signed [15:0] sample_in       = 16'sd0;
    reg [31:0]        gate_cycles     = 32'd12_500;
    reg signed [15:0] threshold       = 16'sd50;
    reg               sync_reset      = 1'b0;
    reg               sync_slave_mode = 1'b0;

    wire [31:0]       count_latched;
    wire [15:0]       amplitude_latched;
    wire              gate_done;

    freq_counter dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .sample_in         (sample_in),
        .gate_cycles       (gate_cycles),
        .threshold         (threshold),
        .sync_reset        (sync_reset),
        .sync_slave_mode   (sync_slave_mode),
        .count_latched     (count_latched),
        .amplitude_latched (amplitude_latched),
        .gate_done         (gate_done)
    );

    always #4 clk = ~clk;   // 125 MHz

    integer errors = 0;
    integer cyc, half, total_half;
    integer expected;

    integer gate_done_pulses = 0;
    reg     gate_done_prev   = 1'b0;
    always @(posedge clk) begin
        gate_done_prev <= gate_done;
        if (gate_done && !gate_done_prev)
            gate_done_pulses <= gate_done_pulses + 1;
    end

    reg [31:0] count_before;
    integer    pulses_before, settle, k;

    initial begin
        $dumpfile("tb_freq.vcd");
        $dumpvars(0, tb_freq_counter);

        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // --- Phase 1: standalone mode, 1 MHz check ---
        sync_slave_mode = 1'b0;
        total_half = 0;
        pulses_before = gate_done_pulses;
        for (cyc = 0; cyc < 13000; cyc = cyc + 1) begin
            @(negedge clk);
            half = (total_half / 62) & 1;
            sample_in = half ? 16'sd5000 : -16'sd5000;
            total_half = total_half + 1;
        end
        while (gate_done_pulses == pulses_before) @(posedge clk);
        if (count_latched < 95 || count_latched > 105) begin
            $display("FAIL: Phase 1 count_latched=%0d, expected ~100", count_latched);
            errors = errors + 1;
        end else
            $display("ok:   Phase 1 — standalone 1 MHz → %0d crossings / 100 us gate", count_latched);

        // --- Phase 2: SLAVE MODE — at_end repeatedly without latching ---
        // Set a very short gate so at_end fires often, but enable slave mode.
        // crossing_cnt should keep accumulating; gate_done shouldn't fire.
        // After several would-be at_ends, fire sync_reset → latches the
        // total accumulated count.
        sync_slave_mode = 1'b1;
        gate_cycles     = 32'd1000;        // very short watchdog gate (~8 us)
        @(posedge clk);                     // let gate_target update

        pulses_before = gate_done_pulses;
        count_before  = count_latched;

        // Drive ~50_000 stim cycles of 1 MHz square wave. That's 50× the
        // gate-cycles value (1000), so the watchdog at_end fires ~50 times.
        // Without latching, crossing_cnt accumulates ~50000/125 = 400 crossings.
        total_half = 0;
        for (cyc = 0; cyc < 50_000; cyc = cyc + 1) begin
            @(negedge clk);
            half = (total_half / 62) & 1;
            sample_in = half ? 16'sd5000 : -16'sd5000;
            total_half = total_half + 1;
        end

        // No new gate_done pulses should have fired.
        if (gate_done_pulses !== pulses_before) begin
            $display("FAIL: Phase 2 — slave-mode at_end fired %0d spurious gate_done(s)",
                     gate_done_pulses - pulses_before);
            errors = errors + 1;
        end else if (count_latched !== count_before) begin
            $display("FAIL: Phase 2 — slave-mode at_end stomped count_latched (%0d -> %0d)",
                     count_before, count_latched);
            errors = errors + 1;
        end else
            $display("ok:   Phase 2a — slave-mode at_end is a watchdog, no latch, no gate_done");

        // Now fire sync_reset → should latch the accumulated crossing_cnt.
        pulses_before = gate_done_pulses;
        @(negedge clk); sync_reset = 1'b1;
        @(negedge clk); sync_reset = 1'b0;
        @(posedge clk);
        @(posedge clk);

        if (gate_done_pulses !== pulses_before + 1) begin
            $display("FAIL: Phase 2b — sync_reset should latch + fire gate_done (got %0d new pulses)",
                     gate_done_pulses - pulses_before);
            errors = errors + 1;
        end else begin
            // Expected count: 50000 stim cycles * (1 rising edge / 125 cycles) = ~400.
            // Allow ±20 for cycle-counting slop.
            if (count_latched < 380 || count_latched > 420) begin
                $display("FAIL: Phase 2b — accumulated count_latched=%0d, expected ~400",
                         count_latched);
                errors = errors + 1;
            end else
                $display("ok:   Phase 2b — sync_reset latches full accumulated count=%0d",
                         count_latched);
        end

        // --- Phase 3: slave mode, sync_reset with no rising edges ---
        // Step 1: transition input to constant high. State may register one
        // rising edge during the transition itself.
        sample_in = 16'sd5000;
        for (settle = 0; settle < 200; settle = settle + 1) @(negedge clk);

        // Step 2: absorb any residual transition-driven crossing with a
        // discard sync_reset. Now crossing_cnt is 0 and state is stable.
        @(negedge clk); sync_reset = 1'b1;
        @(negedge clk); sync_reset = 1'b0;
        for (settle = 0; settle < 200; settle = settle + 1) @(negedge clk);

        // Step 3: with the input truly quiet, fire sync_reset → count = 0
        pulses_before = gate_done_pulses;
        @(negedge clk); sync_reset = 1'b1;
        @(negedge clk); sync_reset = 1'b0;
        @(posedge clk);
        @(posedge clk);

        if (gate_done_pulses !== pulses_before + 1) begin
            $display("FAIL: Phase 3 — sync_reset (quiet) should still fire gate_done");
            errors = errors + 1;
        end else if (count_latched !== 32'd0) begin
            $display("FAIL: Phase 3 — quiet-input slave gave count_latched=%0d, expected 0",
                     count_latched);
            errors = errors + 1;
        end else
            $display("ok:   Phase 3 — slave-mode sync_reset with truly quiet input → count=0");

        // --- Phase 4: standalone mode, sync_reset still latches ---
        // (Single-board operation is unchanged with sync_slave_mode = 0,
        //  but if a stray sync_reset fired it would still latch — verifying
        //  the OR semantics in latch_trigger.)
        sync_slave_mode = 1'b0;
        gate_cycles     = 32'd1000;
        @(posedge clk);

        // Drive an obvious signal so crossing_cnt has something
        sample_in = 16'sd5000;
        for (settle = 0; settle < 200; settle = settle + 1) @(negedge clk);
        // Wait for at_end to fire once (clean state)
        pulses_before = gate_done_pulses;
        while (gate_done_pulses == pulses_before) @(posedge clk);
        $display("Phase 4 setup: at_end fired, count_latched=%0d", count_latched);

        // Now drive 1 MHz stim for a partial gate, then sync_reset
        total_half = 0;
        for (cyc = 0; cyc < 600; cyc = cyc + 1) begin
            @(negedge clk);
            half = (total_half / 62) & 1;
            sample_in = half ? 16'sd5000 : -16'sd5000;
            total_half = total_half + 1;
        end
        pulses_before = gate_done_pulses;
        @(negedge clk); sync_reset = 1'b1;
        @(negedge clk); sync_reset = 1'b0;
        @(posedge clk);
        @(posedge clk);

        if (gate_done_pulses !== pulses_before + 1) begin
            $display("FAIL: Phase 4 — sync_reset in standalone mode failed to latch");
            errors = errors + 1;
        end else
            $display("ok:   Phase 4 — sync_reset in standalone mode latches (count=%0d)",
                     count_latched);

        if (errors == 0) $display("\nPASS: freq_counter tests");
        else             $display("\nFAIL: %0d test(s) failed", errors);
        $finish;
    end

    initial begin
        #2_000_000;
        $display("FAIL: testbench timeout");
        $finish;
    end

endmodule
