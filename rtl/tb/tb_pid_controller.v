`timescale 1ns / 1ps

// Testbench for pid_controller.v.
//
// Models a trivial first-order plant inside the testbench:
//    plant_state ← plant_state + control * plant_gain
// And feeds plant_state back as `measured`. With kp + small ki we should
// converge to the setpoint within a few dozen update_pulses.
//
// Tests:
//   1. With enable=0 the controller stays at 0.
//   2. Step response: setpoint = 1000, plant gain modest, we expect convergence.
//   3. Output saturation: huge setpoint, verify saturated_high = 1 and the
//      integrator stops growing.
module tb_pid_controller;

    reg                  clk             = 0;
    reg                  rst_n           = 0;
    reg                  enable          = 0;
    reg                  update_pulse    = 0;
    reg  signed [31:0]   setpoint        = 0;
    reg  signed [31:0]   measured        = 0;
    reg  signed [15:0]   kp              = 16'sd0;
    reg  signed [15:0]   ki              = 16'sd0;
    reg  signed [31:0]   integ_max       = 32'sd100000;
    reg  signed [31:0]   integ_min       = -32'sd100000;
    reg  signed [31:0]   out_max         = 32'sd50000;
    reg  signed [31:0]   out_min         = -32'sd50000;

    wire signed [31:0]   control;
    wire                 saturated_high;
    wire                 saturated_low;
    wire signed [31:0]   integrator_state;

    pid_controller dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .enable          (enable),
        .update_pulse    (update_pulse),
        .setpoint        (setpoint),
        .measured        (measured),
        .kp              (kp),
        .ki              (ki),
        .integ_max       (integ_max),
        .integ_min       (integ_min),
        .out_max         (out_max),
        .out_min         (out_min),
        .control         (control),
        .saturated_high  (saturated_high),
        .saturated_low   (saturated_low),
        .integrator_state(integrator_state)
    );

    always #4 clk = ~clk;

    integer errors = 0;
    integer i;

    // First-order leaky plant: measured ← 0.9 * measured + 0.1 * control.
    // Steady-state gain = 1, time constant ≈ 10 pulses.
    task plant_step;
        begin
            measured = measured - (measured / 10) + (control / 10);
        end
    endtask

    task pulse;
        begin
            @(negedge clk);
            update_pulse = 1;
            @(negedge clk);
            update_pulse = 0;
            // PID is now 3-stage pipelined: control updates 3 clocks after
            // update_pulse asserted. Wait through that pipeline before
            // returning so the testbench sees the new value.
            repeat (4) @(posedge clk);
            #1;
        end
    endtask

    initial begin
        $dumpfile("tb_pid.vcd");
        $dumpvars(0, tb_pid_controller);

        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // --- Test 1: disabled controller stays at 0 ---
        enable = 0; setpoint = 1000; measured = 0;
        kp = 16'sd4096;  // unity gain
        ki = 16'sd0;
        pulse;
        if (control !== 0) begin
            $display("FAIL: disabled controller emitted %0d", control);
            errors = errors + 1;
        end else $display("ok:   disabled controller emits 0");

        // --- Test 2: closed-loop step response on a leaky plant ---
        // With kp ≈ 1 and a plant that has unity DC gain, the loop's closed-
        // loop bandwidth is ~kp/τ_plant.  ki nudges steady-state error to 0.
        enable = 1;
        kp = 16'sd4096;  // 1.0 in Q4.12
        ki = 16'sd512;   // 0.125 — pushes residual error to zero
        measured = 32'sd0;
        setpoint = 32'sd1000;

        for (i = 0; i < 100; i = i + 1) begin
            pulse;
            plant_step;
            if (i < 10 || i % 10 == 9)
                $display("pulse %3d: measured=%5d  control=%5d  integ=%5d",
                         i, measured, control, integrator_state);
        end

        $display("After 100 pulses: setpoint=1000, measured=%0d, control=%0d, integ=%0d",
                 measured, control, integrator_state);
        if (measured < 950 || measured > 1050) begin
            $display("FAIL: did not converge (measured=%0d, expected ~1000)", measured);
            errors = errors + 1;
        end else $display("ok:   converged to within 5%% of setpoint");

        // --- Test 3: output saturation ---
        // Crank setpoint massively; output should clamp at out_max.
        setpoint = 32'sd100_000_000;   // unreachable
        for (i = 0; i < 50; i = i + 1) begin
            pulse;
            // No plant update — keep plant at 0 so error stays huge
        end
        if (saturated_high !== 1'b1) begin
            $display("FAIL: saturated_high not asserted with huge error");
            errors = errors + 1;
        end else $display("ok:   saturated_high asserted at huge error");
        if (control !== out_max) begin
            $display("FAIL: control = %0d, expected out_max = %0d", control, out_max);
            errors = errors + 1;
        end else $display("ok:   control clamped to out_max");

        // Integrator should not have grown past integ_max
        if (integrator_state > integ_max + 16'sd1) begin
            $display("FAIL: anti-windup failed; integ = %0d (max %0d)", integrator_state, integ_max);
            errors = errors + 1;
        end else $display("ok:   anti-windup held integ = %0d <= %0d", integrator_state, integ_max);

        if (errors == 0) $display("\nPASS: pid_controller tests");
        else             $display("\nFAIL: %0d test(s) failed", errors);
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL: testbench timeout");
        $finish;
    end

endmodule
