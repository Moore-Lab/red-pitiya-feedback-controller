`timescale 1ns / 1ps
// Self-checking testbench for nco_summer (base_tw + (pid_correction << shift), saturated).
module tb_nco_summer;
    reg clk = 0; reg rstn = 0;
    reg  [31:0] base_tw;
    reg  signed [31:0] pid_corr;
    reg  [4:0]  shift_left;
    wire [31:0] actual_tw;

    nco_summer dut(.clk(clk), .rst_n(rstn), .base_tw(base_tw),
                   .pid_correction(pid_corr), .shift_left(shift_left), .actual_tw(actual_tw));

    always #4 clk = ~clk;
    integer errors = 0;

    task apply(input [31:0] b, input signed [31:0] c, input [4:0] s, input [31:0] exp);
        begin
            @(posedge clk); base_tw = b; pid_corr = c; shift_left = s;
            repeat (3) @(posedge clk);   // 2-stage pipeline + margin
            #1;
            if (actual_tw !== exp) begin
                $display("FAIL: base=%0d corr=%0d shift=%0d -> %0d, expected %0d",
                         b, c, s, actual_tw, exp);
                errors = errors + 1;
            end else
                $display("ok: base=%0d corr=%0d shift=%0d -> %0d", b, c, s, actual_tw);
        end
    endtask

    initial begin
        base_tw=0; pid_corr=0; shift_left=0;
        repeat (3) @(posedge clk); rstn = 1;
        apply(32'd1000,  32'sd0,   5'd0,  32'd1000);          // passthrough
        apply(32'd1000,  32'sd5,   5'd2,  32'd1020);          // +5<<2 = +20
        apply(32'd0,    -32'sd10,  5'd0,  32'd0);             // negative -> clamp low
        apply(32'hFFFFFFF0, 32'sd100, 5'd0, 32'hFFFFFFFF);   // overflow -> clamp high
        apply(32'd2000, -32'sd100, 5'd3,  32'd1200);         // -100<<3 = -800
        if (errors == 0) $display("\nPASS: nco_summer tests");
        else             $display("\nFAIL: nco_summer %0d error(s)", errors);
        $finish;
    end
    initial begin #50000; $display("FAIL: nco_summer timeout"); $finish; end
endmodule
