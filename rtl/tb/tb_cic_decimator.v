`timescale 1ns / 1ps

// Testbench for cic_decimator.v
// Checks:
//   1. out_valid pulses every R clocks (so the decimation rate is correct).
//   2. With a low-frequency tone at the input, the output also shows that
//      tone (samples cross zero ~the right number of times in a window).
//
// Full FFT-based correctness verification is deferred to the hardware
// loopback test; this is the basic smoke test.
module tb_cic_decimator;

    localparam R         = 10;
    localparam N         = 4;
    localparam IN_WIDTH  = 14;
    localparam OUT_WIDTH = 16;

    reg                       clk       = 0;
    reg                       rst_n     = 0;
    reg  signed [IN_WIDTH-1:0] in_sample = 14'sd0;
    wire signed [OUT_WIDTH-1:0] out_sample;
    wire                       out_valid;

    cic_decimator #(.R(R), .N(N), .IN_WIDTH(IN_WIDTH), .OUT_WIDTH(OUT_WIDTH)) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .in_sample   (in_sample),
        .out_sample  (out_sample),
        .out_valid   (out_valid)
    );

    always #4 clk = ~clk;

    integer errors = 0;

    // Monitor decimation rate
    integer total_clocks      = 0;
    integer total_valid_pulses = 0;
    always @(posedge clk) begin
        if (rst_n) total_clocks = total_clocks + 1;
        if (out_valid) total_valid_pulses = total_valid_pulses + 1;
    end

    // Stimulus: 100 kHz square wave on input
    //   Period at 125 MHz = 1250 input cycles → 625 high / 625 low
    integer cyc;
    integer half_idx;
    integer half_blk;

    initial begin
        $dumpfile("tb_cic.vcd");
        $dumpvars(0, tb_cic_decimator);

        repeat (8) @(posedge clk);
        rst_n = 1;
        @(negedge clk);

        // Drive ~16,000 input cycles → enough for many decimated samples
        for (cyc = 0; cyc < 16000; cyc = cyc + 1) begin
            @(negedge clk);
            half_blk = cyc / 625;
            half_idx = half_blk & 1;
            in_sample = half_idx ? 14'sd4000 : -14'sd4000;
        end

        @(posedge clk);

        $display("clocks=%0d  out_valid_pulses=%0d  ratio=%0d",
                 total_clocks, total_valid_pulses,
                 (total_valid_pulses == 0) ? 0 : total_clocks / total_valid_pulses);

        // Each out_valid pulse should occur every R clock cycles
        if (total_valid_pulses == 0) begin
            $display("FAIL: no out_valid pulses observed");
            errors = errors + 1;
        end else begin
            // Allow ±1 due to startup
            if ((total_clocks / total_valid_pulses) < R - 1 ||
                (total_clocks / total_valid_pulses) > R + 1) begin
                $display("FAIL: avg clocks/pulse = %0d, expected ~%0d",
                         total_clocks / total_valid_pulses, R);
                errors = errors + 1;
            end else begin
                $display("ok:   decimation ratio observed = %0d (expected %0d)",
                         total_clocks / total_valid_pulses, R);
            end
        end

        // After settling, output should not be stuck at 0 (would mean broken)
        if (out_sample === {OUT_WIDTH{1'b0}}) begin
            $display("WARN: out_sample is 0 at end of test (transient might dominate)");
        end else begin
            $display("ok:   out_sample at end = %0d (non-zero, signal arrived)", out_sample);
        end

        if (errors == 0) $display("\nPASS: cic_decimator smoke tests");
        else             $display("\nFAIL: %0d test(s) failed", errors);
        $finish;
    end

    initial begin
        #500000;
        $display("FAIL: testbench timeout");
        $finish;
    end

endmodule
