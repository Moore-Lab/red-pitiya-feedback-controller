`timescale 1ns / 1ps
// Self-checking testbench for sign_extend_14to16 (14-bit signed -> 16-bit signed).
module tb_sign_extend_14to16;
    reg  signed [13:0] in;
    wire signed [15:0] out;
    integer errors = 0;

    sign_extend_14to16 dut(.in(in), .out(out));

    task chk(input signed [13:0] v, input signed [15:0] exp);
        begin
            in = v; #1;
            if (out !== exp) begin
                $display("FAIL: in=%0d -> %0d, expected %0d", v, out, exp);
                errors = errors + 1;
            end else
                $display("ok: in=%0d -> %0d", v, out);
        end
    endtask

    initial begin
        chk(14'sd0,     16'sd0);
        chk(14'sd8191,  16'sd8191);    // max positive
        chk(-14'sd8192, -16'sd8192);   // max negative
        chk(-14'sd1,    -16'sd1);      // sign bit propagates
        chk(14'sd100,   16'sd100);
        if (errors == 0) $display("\nPASS: sign_extend_14to16 tests");
        else             $display("\nFAIL: sign_extend_14to16 %0d error(s)", errors);
        $finish;
    end
endmodule
