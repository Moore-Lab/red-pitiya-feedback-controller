`timescale 1ns / 1ps
// Self-checking testbench for adc_mux (combinational 2:1 select on a signed 14-bit stream).
module tb_adc_mux;
    reg signed [13:0] a, b;
    reg sel;
    wire signed [13:0] out;
    integer errors = 0;

    adc_mux dut(.adc_a(a), .adc_b(b), .select(sel), .adc_out(out));

    task chk(input signed [13:0] exp);
        begin
            #1;
            if (out !== exp) begin
                $display("FAIL: a=%0d b=%0d sel=%b -> %0d, expected %0d", a, b, sel, out, exp);
                errors = errors + 1;
            end else
                $display("ok: a=%0d b=%0d sel=%b -> %0d", a, b, sel, out);
        end
    endtask

    initial begin
        a = 14'sd1234;  b = -14'sd2000;
        sel = 1'b0; chk(14'sd1234);
        sel = 1'b1; chk(-14'sd2000);
        a = -14'sd1;   b = 14'sd8191;   // most-negative-ish / most-positive
        sel = 1'b0; chk(-14'sd1);
        sel = 1'b1; chk(14'sd8191);
        if (errors == 0) $display("\nPASS: adc_mux tests");
        else             $display("\nFAIL: adc_mux %0d error(s)", errors);
        $finish;
    end
endmodule
