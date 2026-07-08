`timescale 1ns / 1ps

// Testbench for sync_io.v — covers the five cases from
// docs/multi_board_test_plan.md §2.1.
//
// Compile with -DSIM so IBUFDS / OBUFDS are swapped for plain wires.
//   iverilog -DSIM -o tb_sync_io.out tb/tb_sync_io.v src/sync_io.v
//   vvp tb_sync_io.out
//
// Checks:
//   1. Default (all bits 0):  master_pulse cannot reach daisy_p_o; received
//                             daisy_p_i pulses cannot reach sync_reset.
//   2. Master only:           one master_pulse → exactly one daisy_p_o rise.
//   3. Slave only:            long-held daisy_p_i input → exactly one
//                             sync_reset pulse (no chatter).
//   4. Retransmit:            input edge → exactly one daisy_p_o rise AND
//                             one local sync_reset on the same input edge.
//   5. Async-phase input:     daisy_p_i toggled in arbitrary sub-cycle
//                             phase → 1 sync_reset per edge, each exactly
//                             1 clock cycle wide.
module tb_sync_io;
    reg clk = 0;
    reg rst_n = 0;
    reg sync_master_enable     = 0;
    reg sync_slave_enable      = 0;
    reg sync_retransmit_enable = 0;
    reg master_pulse           = 0;
    reg daisy_p_i              = 0;
    reg daisy_n_i              = 1;  // unused in SIM

    wire daisy_p_o, daisy_n_o;
    wire sync_reset;

    sync_io dut (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .sync_master_enable     (sync_master_enable),
        .sync_slave_enable      (sync_slave_enable),
        .sync_retransmit_enable (sync_retransmit_enable),
        .master_pulse           (master_pulse),
        .daisy_p_o              (daisy_p_o),
        .daisy_n_o              (daisy_n_o),
        .daisy_p_i              (daisy_p_i),
        .daisy_n_i              (daisy_n_i),
        .sync_reset             (sync_reset)
    );

    always #4 clk = ~clk;   // 125 MHz

    integer errors = 0;

    // sync_reset pulse counter and width sanity tracker. If every assertion
    // is exactly 1 cycle wide, total high-cycles == total pulses.
    integer sync_reset_pulses      = 0;
    integer sync_reset_high_cycles = 0;
    always @(posedge clk) begin
        if (sync_reset) begin
            sync_reset_high_cycles <= sync_reset_high_cycles + 1;
        end
    end
    reg sync_reset_prev = 0;
    always @(posedge clk) begin
        sync_reset_prev <= sync_reset;
        if (sync_reset && !sync_reset_prev)
            sync_reset_pulses <= sync_reset_pulses + 1;
    end

    // daisy_p_o rising-edge counter
    reg daisy_p_o_prev = 0;
    integer daisy_p_o_rises = 0;
    always @(posedge clk) begin
        daisy_p_o_prev <= daisy_p_o;
        if (daisy_p_o && !daisy_p_o_prev)
            daisy_p_o_rises <= daisy_p_o_rises + 1;
    end

    task pulse_master_one_cycle;
        begin
            @(negedge clk); master_pulse = 1'b1;
            @(negedge clk); master_pulse = 1'b0;
        end
    endtask

    // Hold daisy_p_i high for N clock cycles, aligned to negedge.
    task pulse_daisy_in;
        input integer n;
        begin
            @(negedge clk); daisy_p_i = 1'b1;
            repeat (n) @(negedge clk);
            daisy_p_i = 1'b0;
        end
    endtask

    integer pulses_before, rises_before, k;

    initial begin
        $dumpfile("tb_sync_io.vcd");
        $dumpvars(0, tb_sync_io);

        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (4) @(posedge clk);

        // --- 1. Default (all bits 0) ---
        sync_master_enable     = 0;
        sync_slave_enable      = 0;
        sync_retransmit_enable = 0;
        rises_before  = daisy_p_o_rises;
        pulses_before = sync_reset_pulses;

        pulse_master_one_cycle;
        repeat (5) @(posedge clk);
        if (daisy_p_o_rises !== rises_before) begin
            $display("FAIL [default]: daisy_p_o rose despite reg27=0 (count %0d)",
                     daisy_p_o_rises - rises_before);
            errors = errors + 1;
        end else $display("ok:   default: master_pulse cannot reach daisy_p_o");

        pulse_daisy_in(5);
        repeat (5) @(posedge clk);
        if (sync_reset_pulses !== pulses_before) begin
            $display("FAIL [default]: sync_reset fired despite reg27=0 (count %0d)",
                     sync_reset_pulses - pulses_before);
            errors = errors + 1;
        end else $display("ok:   default: daisy_p_i edge cannot reach sync_reset");

        // --- 2. Master only ---
        sync_master_enable     = 1;
        sync_slave_enable      = 0;
        sync_retransmit_enable = 0;
        daisy_p_i = 0;
        repeat (3) @(posedge clk);
        rises_before = daisy_p_o_rises;

        pulse_master_one_cycle;
        repeat (3) @(posedge clk);
        if (daisy_p_o_rises !== rises_before + 1) begin
            $display("FAIL [master]: expected 1 daisy_p_o rise, got %0d",
                     daisy_p_o_rises - rises_before);
            errors = errors + 1;
        end else $display("ok:   master: master_pulse → 1 daisy_p_o rise");

        // --- 3. Slave only: long-held high → single sync_reset pulse ---
        sync_master_enable     = 0;
        sync_slave_enable      = 1;
        sync_retransmit_enable = 0;
        master_pulse = 0;
        daisy_p_i = 0;
        repeat (5) @(posedge clk);    // let synchroniser settle low
        pulses_before = sync_reset_pulses;

        pulse_daisy_in(8);
        repeat (8) @(posedge clk);
        if (sync_reset_pulses !== pulses_before + 1) begin
            $display("FAIL [slave]: long high gave %0d sync_resets, expected 1",
                     sync_reset_pulses - pulses_before);
            errors = errors + 1;
        end else $display("ok:   slave: long daisy_p_i high → 1 sync_reset pulse");

        // --- 4. Retransmit + slave: incoming edge → one daisy_p_o rise + one sync_reset ---
        sync_master_enable     = 0;
        sync_slave_enable      = 1;
        sync_retransmit_enable = 1;
        daisy_p_i = 0;
        repeat (5) @(posedge clk);
        rises_before  = daisy_p_o_rises;
        pulses_before = sync_reset_pulses;

        pulse_daisy_in(6);
        repeat (10) @(posedge clk);

        if (daisy_p_o_rises !== rises_before + 1) begin
            $display("FAIL [retransmit]: expected 1 daisy_p_o rise, got %0d",
                     daisy_p_o_rises - rises_before);
            errors = errors + 1;
        end else $display("ok:   retransmit: input edge → 1 daisy_p_o rise");

        if (sync_reset_pulses !== pulses_before + 1) begin
            $display("FAIL [retransmit]: expected 1 sync_reset, got %0d",
                     sync_reset_pulses - pulses_before);
            errors = errors + 1;
        end else $display("ok:   retransmit: input edge → 1 local sync_reset");

        // --- 5. Async-phase input: daisy_p_i toggled at arbitrary sub-cycle phase ---
        sync_master_enable     = 0;
        sync_slave_enable      = 1;
        sync_retransmit_enable = 0;
        daisy_p_i = 0;
        repeat (8) @(posedge clk);
        pulses_before = sync_reset_pulses;

        for (k = 0; k < 5; k = k + 1) begin
            #3; #3; #3;             // 9 ns offset (not aligned to 8 ns clock)
            daisy_p_i = 1'b1;
            #3; #3; #3; #3;         // 12 ns high
            daisy_p_i = 1'b0;
            #3; #3; #3; #3; #3;     // 15 ns recovery
        end
        repeat (10) @(posedge clk);

        if (sync_reset_pulses !== pulses_before + 5) begin
            $display("FAIL [async]: expected 5 sync_reset pulses, got %0d",
                     sync_reset_pulses - pulses_before);
            errors = errors + 1;
        end else $display("ok:   async: 5 edges → 5 sync_reset pulses");

        if (sync_reset_high_cycles !== sync_reset_pulses) begin
            $display("FAIL [width]: high_cycles=%0d != pulses=%0d (sync_reset wider than 1 cycle somewhere)",
                     sync_reset_high_cycles, sync_reset_pulses);
            errors = errors + 1;
        end else $display("ok:   every sync_reset is exactly 1 clock cycle wide (%0d total)",
                          sync_reset_pulses);

        if (errors == 0) $display("\nPASS: sync_io tests");
        else             $display("\nFAIL: %0d test(s) failed", errors);
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL: testbench timeout");
        $finish;
    end

endmodule
