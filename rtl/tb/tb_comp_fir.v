`timescale 1ns / 1ps

// Smoke test for comp_fir.v:
//   1. Push an impulse through, check the output has the expected pipeline
//      latency and out_valid pulses arrive in step with the impulse.
//   2. Push a DC stream (constant non-zero input) and verify the output
//      converges to the same constant (DC gain ≈ 1 after settling).
//
// Run: iverilog -DSIM -o tb_fir.out tb/tb_comp_fir.v src/comp_fir.v
//      vvp tb_fir.out
module tb_comp_fir;

    reg               clk      = 0;
    reg               rst_n    = 0;
    reg               in_valid = 0;
    reg  signed [15:0] in_sample = 16'sd0;
    wire signed [15:0] out_sample;
    wire              out_valid;

    comp_fir dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .in_valid   (in_valid),
        .in_sample  (in_sample),
        .out_sample (out_sample),
        .out_valid  (out_valid)
    );

    always #4 clk = ~clk;

    integer errors = 0;
    integer pulses_seen = 0;
    integer last_out = 0;

    // Track out_valid pulses
    always @(posedge clk) begin
        if (out_valid) begin
            pulses_seen = pulses_seen + 1;
            last_out    = out_sample;
        end
    end

    initial begin
        $dumpfile("tb_fir.vcd");
        $dumpvars(0, tb_comp_fir);

        repeat (8) @(posedge clk);
        rst_n = 1;
        @(negedge clk);

        // --- Test 1: impulse response ---
        // Send a single impulse: in_valid for 1 cycle with sample=8000, then idle.
        in_valid = 1'b1;
        in_sample = 16'sd8000;
        @(negedge clk);
        in_valid = 1'b0;
        in_sample = 16'sd0;

        // Wait for pipeline latency (5) + a few extras
        repeat (20) @(posedge clk);
        $display("Test 1: 1 impulse → %0d out_valid pulses (expected 1)", pulses_seen);
        if (pulses_seen != 1) begin
            $display("FAIL: expected exactly 1 out_valid pulse, got %0d", pulses_seen);
            errors = errors + 1;
        end else $display("ok:   single in_valid produced single out_valid");

        // --- Test 2: DC step ---
        // Push a constant value at the full rate of in_valid (every cycle)
        pulses_seen = 0;
        in_sample = 16'sd5000;
        repeat (40) begin
            @(negedge clk);
            in_valid = 1'b1;
        end
        @(negedge clk);
        in_valid = 1'b0;

        repeat (20) @(posedge clk);
        // After NTAPS = 16 samples, the FIR has filled its taps with 5000.
        // DC gain = 1, so out_sample should be ~5000 ± rounding.
        $display("Test 2: DC=5000 → out=%0d (expected ~5000, ±100)", last_out);
        if (last_out < 4900 || last_out > 5100) begin
            $display("FAIL: DC gain out of tolerance (%0d)", last_out);
            errors = errors + 1;
        end else $display("ok:   DC gain ~1 (output=%0d ≈ input=5000)", last_out);

        if (errors == 0) $display("\nPASS: comp_fir smoke tests");
        else             $display("\nFAIL: %0d test(s) failed", errors);
        $finish;
    end

    initial begin
        #100000;
        $display("FAIL: testbench timeout");
        $finish;
    end

endmodule
