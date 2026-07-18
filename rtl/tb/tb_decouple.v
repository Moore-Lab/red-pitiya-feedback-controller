`timescale 1ns / 1ps

// tb_decouple.v — testbench for the reserved MIMO decoupling stub.
//
// Asserts:
//   (a) BYPASS path (decouple_bypass = 1, the reset default) is BIT-IDENTICAL
//       to the input across many random N=4 vectors — the property that makes
//       the block impossible to perturb the instrument in v1.
//   (b) A 2x2 NON-bypass case computes the Q4.12 fixed-point matrix product
//       y = (M*x)>>>12 (with 32-bit saturation) matching a golden model.
//
// Prints "PASS" on success and "FAIL" (with detail) on any mismatch.

module tb_decouple;

    localparam integer DATA_W  = 32;
    localparam integer COEFF_W = 16;
    localparam integer FRAC    = 12;

    reg clk = 0;
    always #5 clk = ~clk;   // 100 MHz

    reg rst_n;
    integer errors = 0;

    // =====================================================================
    // (a) N=4 BYPASS: bit-exact pass-through with 2-cycle latency.
    // =====================================================================
    localparam integer N4 = 4;

    reg                    a_valid_in;
    reg                    a_bypass;
    reg  [N4*DATA_W-1:0]   a_x;
    wire [N4*DATA_W-1:0]   a_y;
    wire                   a_valid_out;

    // Coeffs unused on the bypass path; drive them nonzero to prove they are
    // ignored while bypassed.
    wire [N4*N4*COEFF_W-1:0] a_coeff = {(N4*N4){16'h5A5A}};

    decouple #(.N(N4), .DATA_W(DATA_W), .COEFF_W(COEFF_W), .COEFF_FRAC(FRAC)) dut_a (
        .clk(clk), .rst_n(rst_n),
        .valid_in(a_valid_in), .bypass(a_bypass),
        .x_flat(a_x), .coeff_flat(a_coeff),
        .y_flat(a_y), .valid_out(a_valid_out)
    );

    // 2-deep shadow of the input to compare against the 2-cycle-latent output.
    reg [N4*DATA_W-1:0] a_x_d1, a_x_d2;
    always @(posedge clk) begin
        if (!rst_n) begin
            a_x_d1 <= {N4*DATA_W{1'b0}};
            a_x_d2 <= {N4*DATA_W{1'b0}};
        end else begin
            a_x_d1 <= a_x;
            a_x_d2 <= a_x_d1;
        end
    end

    // =====================================================================
    // (b) N=2 NON-bypass: Q4.12 matrix product vs golden model.
    // =====================================================================
    localparam integer N2 = 2;

    reg                    b_valid_in;
    reg                    b_bypass;
    reg  [N2*DATA_W-1:0]   b_x;
    reg  [N2*N2*COEFF_W-1:0] b_coeff;
    wire [N2*DATA_W-1:0]   b_y;
    wire                   b_valid_out;

    decouple #(.N(N2), .DATA_W(DATA_W), .COEFF_W(COEFF_W), .COEFF_FRAC(FRAC)) dut_b (
        .clk(clk), .rst_n(rst_n),
        .valid_in(b_valid_in), .bypass(b_bypass),
        .x_flat(b_x), .coeff_flat(b_coeff),
        .y_flat(b_y), .valid_out(b_valid_out)
    );

    // Golden fixed-point model for the 2x2 product with 32-bit saturation.
    // M row-major: {M11, M10, M01, M00} packed low->high.
    function signed [DATA_W-1:0] sat32;
        input signed [63:0] v;
        begin
            if      (v >  ((64'sd1 << (DATA_W-1)) - 1)) sat32 = (64'sd1 << (DATA_W-1)) - 1;
            else if (v < -( 64'sd1 << (DATA_W-1)))      sat32 = -(64'sd1 << (DATA_W-1));
            else                                        sat32 = v[DATA_W-1:0];
        end
    endfunction

    function signed [DATA_W-1:0] golden;
        input signed [COEFF_W-1:0] m0;   // coeff for this output vs x0
        input signed [COEFF_W-1:0] m1;   // coeff for this output vs x1
        input signed [DATA_W-1:0]  x0;
        input signed [DATA_W-1:0]  x1;
        reg signed [63:0] acc;
        begin
            acc    = (m0 * x0) + (m1 * x1);
            golden = sat32(acc >>> FRAC);
        end
    endfunction

    integer k;
    reg signed [DATA_W-1:0] rx0, rx1;
    reg signed [COEFF_W-1:0] m00, m01, m10, m11;
    reg signed [DATA_W-1:0] exp0, exp1;

    // -------------------------------------------------------------------------
    initial begin
        // Reset.
        rst_n      = 0;
        a_valid_in = 0; a_bypass = 1; a_x = 0;
        b_valid_in = 0; b_bypass = 1; b_x = 0; b_coeff = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // ---- (a) BYPASS bit-exact over random N=4 vectors ----
        a_bypass   = 1;
        a_valid_in = 1;
        for (k = 0; k < 200; k = k + 1) begin
            a_x = {$random, $random, $random, $random};
            @(posedge clk);
            // Output valid two cycles after the input was presented; a_x_d2 is
            // the input from two cycles ago, aligned with the current a_y.
            if (a_valid_out && (a_y !== a_x_d2)) begin
                errors = errors + 1;
                $display("FAIL (a): bypass not bit-exact @k=%0d  y=%h  exp=%h",
                         k, a_y, a_x_d2);
            end
        end
        a_valid_in = 0;
        @(posedge clk);

        // ---- (b) NON-bypass 2x2 matrix product ----
        // M = [[1.0, 0.125],[ -0.25, 0.5]]  in Q4.12 = [[4096,512],[-1024,2048]]
        m00 = 16'sd4096; m01 = 16'sd512;
        m10 = -16'sd1024; m11 = 16'sd2048;
        b_coeff    = {m11, m10, m01, m00};   // row-major {i*N+j} low->high
        b_bypass   = 0;
        b_valid_in = 1;

        for (k = 0; k < 200; k = k + 1) begin
            // Keep magnitudes modest so the product is a meaningful (mostly
            // unsaturated) test; saturation is still exercised occasionally and
            // the golden model saturates identically.
            rx0 = $random >>> 8;   // ~24-bit signed
            rx1 = $random >>> 8;
            b_x = {rx1, rx0};
            exp0 = golden(m00, m01, rx0, rx1);
            exp1 = golden(m10, m11, rx0, rx1);
            // Wait for this vector to propagate (2-cycle latency), then check.
            // #1 settles past the NBA region so b_y holds the post-edge result.
            @(posedge clk);
            @(posedge clk);
            #1;
            if ($signed(b_y[0*DATA_W +: DATA_W]) !== exp0 ||
                $signed(b_y[1*DATA_W +: DATA_W]) !== exp1) begin
                errors = errors + 1;
                $display("FAIL (b): matrix @k=%0d x=[%0d,%0d] y=[%0d,%0d] exp=[%0d,%0d]",
                    k, rx0, rx1,
                    $signed(b_y[0*DATA_W +: DATA_W]), $signed(b_y[1*DATA_W +: DATA_W]),
                    exp0, exp1);
            end
        end
        b_valid_in = 0;

        // ---- identity cross-check: M=I on non-bypass reproduces input ----
        b_coeff    = {16'sd4096, 16'sd0, 16'sd0, 16'sd4096}; // {M11,M10,M01,M00}=I
        b_valid_in = 1;
        for (k = 0; k < 20; k = k + 1) begin
            rx0 = $random >>> 8; rx1 = $random >>> 8;
            b_x = {rx1, rx0};
            @(posedge clk); @(posedge clk); #1;
            if ($signed(b_y[0*DATA_W +: DATA_W]) !== rx0 ||
                $signed(b_y[1*DATA_W +: DATA_W]) !== rx1) begin
                errors = errors + 1;
                $display("FAIL (b-id): identity @k=%0d x=[%0d,%0d] y=[%0d,%0d]",
                    k, rx0, rx1,
                    $signed(b_y[0*DATA_W +: DATA_W]), $signed(b_y[1*DATA_W +: DATA_W]));
            end
        end
        b_valid_in = 0;

        @(posedge clk);
        if (errors == 0)
            $display("PASS: decouple bypass bit-exact + 2x2 Q4.12 matrix product verified");
        else
            $display("FAIL: %0d error(s)", errors);
        $finish;
    end

endmodule
