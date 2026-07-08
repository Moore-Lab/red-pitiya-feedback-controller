`timescale 1ns / 1ps

// Testbench for dac_sine.v
// Verifies:
//   1. Output is zero when enable=0.
//   2. Phase accumulator increments correctly and produces ~sinusoidal output.
//   3. Frequency: count zero-crossings over a fixed window, compare to expected.
//   4. Amplitude scaling: peak value at half-amplitude is ~half the full-scale peak.
//   5. phase_reset returns phase to 0.
//
// Run:
//   iverilog -o tb_dac_sine.out tb/tb_dac_sine.v src/dac_sine.v
//   vvp tb_dac_sine.out
module tb_dac_sine;

    reg                clk         = 0;
    reg                rst_n       = 0;
    reg                enable      = 0;
    reg                phase_reset = 0;
    reg  [31:0]        tuning_word = 32'd0;
    reg  [13:0]        amplitude   = 14'd0;
    wire signed [13:0] dac_out;

    dac_sine #(.LUT_DEPTH(12), .DAC_WIDTH(14)) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .enable      (enable),
        .phase_reset (phase_reset),
        .tuning_word (tuning_word),
        .amplitude   (amplitude),
        .dac_out     (dac_out)
    );

    // 125 MHz clock (8 ns period)
    always #4 clk = ~clk;

    // Track peak magnitudes and zero-crossings
    integer pos_peak;
    integer neg_peak;
    integer zero_crossings;
    reg signed [13:0] prev_dac;

    integer errors = 0;

    initial begin
        $dumpfile("tb_dac_sine.vcd");
        $dumpvars(0, tb_dac_sine);

        repeat (4) @(posedge clk);
        rst_n = 1;

        // --- 1. Output is zero when enable=0 ---
        amplitude   = 14'h3FFF;
        tuning_word = 32'h0010_0000;  // small frequency
        repeat (20) @(posedge clk);
        if (dac_out !== 14'sd0) begin
            $display("FAIL: dac_out=%0d, expected 0 with enable=0", dac_out);
            errors = errors + 1;
        end else
            $display("ok:   dac_out = 0 when enable=0");

        // --- 2,3. Frequency: tuning_word produces correct # of cycles ---
        // Pick tuning_word so that we get exactly 4 cycles in 4096 clock periods.
        // freq = (tw / 2^32) * f_clk
        // cycles per N clocks = freq * N / f_clk = (tw * N) / 2^32
        // For tw = 2^22 and N = 4096: cycles = 2^22 * 2^12 / 2^32 = 2^2 = 4 cycles
        tuning_word = 32'd4194304;  // = 2^22
        amplitude   = 14'h3FFF;
        enable      = 1;
        phase_reset = 1;
        @(posedge clk);
        phase_reset = 0;

        // wait pipeline (4 cycles)
        repeat (8) @(posedge clk);

        // Sample 4096 cycles and count positive-going zero crossings
        pos_peak       = 0;
        neg_peak       = 0;
        zero_crossings = 0;
        prev_dac       = dac_out;
        begin : sample_loop
            integer n;
            for (n = 0; n < 4096; n = n + 1) begin
                @(posedge clk);
                if (dac_out > pos_peak) pos_peak = dac_out;
                if (dac_out < neg_peak) neg_peak = dac_out;
                if (prev_dac < 0 && dac_out >= 0) zero_crossings = zero_crossings + 1;
                prev_dac = dac_out;
            end
        end

        $display("    sampled: pos_peak=%0d neg_peak=%0d zero_crossings=%0d",
                 pos_peak, neg_peak, zero_crossings);

        if (zero_crossings == 4)
            $display("ok:   frequency: 4 positive zero-crossings in 4096 cycles (= 4 sine cycles)");
        else begin
            $display("FAIL: expected 4 zero-crossings, got %0d", zero_crossings);
            errors = errors + 1;
        end

        if (pos_peak > 8000 && pos_peak < 8192)
            $display("ok:   full-amp peak ~ %0d (expected ~8190)", pos_peak);
        else begin
            $display("FAIL: full-amp peak %0d outside [8000,8192]", pos_peak);
            errors = errors + 1;
        end

        // --- 4. Amplitude scaling: half amplitude => half peak ---
        amplitude   = 14'h2000;  // 8192 = ~half scale
        phase_reset = 1;
        @(posedge clk);
        phase_reset = 0;
        repeat (8) @(posedge clk);  // pipeline

        pos_peak = 0;
        begin : amp_loop
            integer n;
            for (n = 0; n < 4096; n = n + 1) begin
                @(posedge clk);
                if (dac_out > pos_peak) pos_peak = dac_out;
            end
        end
        if (pos_peak > 3800 && pos_peak < 4200)
            $display("ok:   half-amp peak %0d ~ 8192/2 = 4096", pos_peak);
        else begin
            $display("FAIL: half-amp peak %0d outside [3800,4200]", pos_peak);
            errors = errors + 1;
        end

        // --- 5. phase_reset holds phase at 0 ---
        // Assert phase_reset for the full pipeline depth (4 cycles) so the
        // accumulator can't advance while we wait for sin(0)=0 to appear.
        amplitude   = 14'h3FFF;
        phase_reset = 1;
        repeat (5) @(posedge clk);
        // Now sample several cycles: phase_acc=0, sin(0)=0, dac_out=0.
        begin : reset_check
            integer n;
            integer fails;
            fails = 0;
            for (n = 0; n < 4; n = n + 1) begin
                @(posedge clk);
                if (dac_out !== 14'sd0) fails = fails + 1;
            end
            if (fails == 0)
                $display("ok:   phase_reset holds dac_out at 0");
            else begin
                $display("FAIL: phase_reset: %0d/4 samples non-zero", fails);
                errors = errors + 1;
            end
        end

        if (errors == 0) $display("\nPASS: all dac_sine tests");
        else             $display("\nFAIL: %0d test(s) failed", errors);
        $finish;
    end

    // Watchdog
    initial begin
        #2000000;
        $display("FAIL: testbench timeout");
        $finish;
    end

endmodule
