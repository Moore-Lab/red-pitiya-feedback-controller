`timescale 1ns / 1ps

// Testbench for blinker.v
// Drives enable=1 and half_period=5 so led toggles every 5 clock cycles.
// Run: iverilog -o tb_blinker tb/tb_blinker.v src/blinker.v && vvp tb_blinker
module tb_blinker;

    reg  clk         = 0;
    reg  rst_n       = 0;
    reg  enable      = 0;
    reg  [31:0] half_period = 32'd5;
    wire led;

    blinker dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .enable      (enable),
        .half_period (half_period),
        .led         (led)
    );

    // 8 ns period (models 125 MHz)
    always #4 clk = ~clk;

    integer transitions = 0;

    initial begin
        $dumpfile("tb_blinker.vcd");
        $dumpvars(0, tb_blinker);

        // Hold reset for 4 cycles
        repeat (4) @(posedge clk);
        rst_n  = 1;
        enable = 1;

        // Wait for 4 full LED transitions (2 blink cycles)
        @(posedge led); transitions = transitions + 1;
        @(negedge led); transitions = transitions + 1;
        @(posedge led); transitions = transitions + 1;
        @(negedge led); transitions = transitions + 1;

        $display("PASS: observed %0d LED transitions", transitions);
        $finish;
    end

endmodule
