`timescale 1ns / 1ps

// Testbench for lock_acquisition.v
// Checks:
//   1. lock_enable=0 passes manual_tw through; locked stays 0.
//   2. With lock_enable=1, base_tw ramps toward target_tw at ramp_rate per pulse.
//   3. Once measured_count is within capture_window of setpoint_count, locked
//      goes high and base_tw freezes.
module tb_lock_acquisition;

    reg               clk            = 0;
    reg               rst_n          = 0;
    reg               lock_enable    = 0;
    reg               update_pulse   = 0;
    reg  [31:0]       manual_tw      = 32'd0;
    reg  [31:0]       target_tw      = 32'd0;
    reg  [31:0]       ramp_rate      = 32'd0;
    reg  signed [31:0] measured_count = 32'sd0;
    reg  signed [31:0] setpoint_count = 32'sd0;
    reg  [31:0]       capture_window = 32'd0;

    wire [31:0]       base_tw;
    wire              locked;

    lock_acquisition dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .lock_enable    (lock_enable),
        .update_pulse   (update_pulse),
        .manual_tw      (manual_tw),
        .target_tw      (target_tw),
        .ramp_rate      (ramp_rate),
        .measured_count (measured_count),
        .setpoint_count (setpoint_count),
        .capture_window (capture_window),
        .base_tw        (base_tw),
        .locked         (locked)
    );

    always #4 clk = ~clk;

    integer errors = 0;

    task pulse;
        begin
            @(negedge clk);
            update_pulse = 1;
            @(negedge clk);
            update_pulse = 0;
            @(posedge clk); #1;
        end
    endtask

    initial begin
        $dumpfile("tb_lock.vcd");
        $dumpvars(0, tb_lock_acquisition);

        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk); #1;

        // ---- Test 1: lock_enable=0 → passthrough ----
        manual_tw      = 32'h1234_5678;
        target_tw      = 32'h8000_0000;
        ramp_rate      = 32'd100_000;
        capture_window = 32'd10;
        setpoint_count = 32'sd10000;
        measured_count = 32'sd0;

        pulse;
        if (base_tw !== 32'h1234_5678 || locked !== 1'b0) begin
            $display("FAIL: passthrough; base_tw=%h, locked=%b", base_tw, locked);
            errors = errors + 1;
        end else $display("ok:   lock_enable=0 → passthrough");

        // ---- Test 2: ramp toward target_tw ----
        // Set big error, expect base_tw to grow each pulse by ramp_rate
        manual_tw      = 32'd0;
        target_tw      = 32'd10_000_000;
        ramp_rate      = 32'd100_000;
        measured_count = 32'sd0;     // far from setpoint
        setpoint_count = 32'sd10000;
        capture_window = 32'd10;

        lock_enable = 1;
        @(posedge clk); #1;  // let it move from IDLE to RAMPING
        pulse;
        if (base_tw < 32'd50_000 || base_tw > 32'd200_000) begin
            $display("FAIL: ramp 1 step; base_tw=%0d (expected ~100000)", base_tw);
            errors = errors + 1;
        end else $display("ok:   ramp first pulse base_tw=%0d", base_tw);

        // Run more pulses; verify monotonic increase
        repeat (5) pulse;
        if (base_tw < 32'd500_000) begin
            $display("FAIL: ramp not progressing; base_tw=%0d", base_tw);
            errors = errors + 1;
        end else $display("ok:   ramp progressed: base_tw=%0d", base_tw);

        // ---- Test 3: lock when measurement enters window ----
        // Suddenly the loopback "reads" within the window
        measured_count = setpoint_count - 32'sd5;  // error = +5, within capture_window=10
        // error_abs is registered, so wait one clock for it to reflect the new
        // measured_count before firing the update pulse.
        @(posedge clk); #1;
        pulse;
        if (!locked) begin
            $display("FAIL: should have locked (error within window)");
            errors = errors + 1;
        end else $display("ok:   locked when error <= capture_window");

        // Once locked, base_tw should hold even with new pulses
        begin : hold_check
            reg [31:0] held_tw;
            held_tw = base_tw;
            pulse;
            pulse;
            if (base_tw !== held_tw) begin
                $display("FAIL: base_tw changed after lock (was %h, now %h)", held_tw, base_tw);
                errors = errors + 1;
            end else $display("ok:   base_tw frozen after lock");
        end

        // ---- Test 4: disabling lock returns to passthrough ----
        lock_enable = 0;
        @(posedge clk); #1;
        if (base_tw !== manual_tw || locked !== 1'b0) begin
            $display("FAIL: disable; base_tw=%h, locked=%b", base_tw, locked);
            errors = errors + 1;
        end else $display("ok:   disable → passthrough, locked cleared");

        if (errors == 0) $display("\nPASS: lock_acquisition tests");
        else             $display("\nFAIL: %0d test(s) failed", errors);
        $finish;
    end

    initial begin
        #100000;
        $display("FAIL: testbench timeout");
        $finish;
    end

endmodule
