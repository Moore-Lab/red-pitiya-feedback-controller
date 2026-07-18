`timescale 1ns / 1ps

// decouple.v — reserved hook for the FUTURE on-FPGA cross-talk-cancellation
// (MIMO decoupling) plane. See framework ARCHITECTURE §3 and INTERFACES §1
// "Reserved for the future on-FPGA decoupling plane".
//
// This is a STUB in v1: it is NOT wired into any live control path. It exists
// so the register contract (`decouple_bypass`, `decouple_coeff[..]`) has a
// concrete, simulated implementation to bind to when the MIMO plane is turned
// on later. It is impossible for this block to perturb the instrument in v1
// because `bypass` resets to 1 (the RTL default) and the bypass path is a
// provably bit-exact copy of the input.
//
// FUNCTION
//   An N-channel fixed-point decoupling matrix on the per-axis control values
//   (axis order [x,y,z,spin]). Each cycle a `valid_in` strobe presents the N
//   control words on `x_flat`:
//
//     bypass = 1  ->  y_i = x_i                       (BIT-EXACT pass-through)
//     bypass = 0  ->  y_i = sat32( ( sum_j M_ij * x_j ) >>> COEFF_FRAC )
//
//   where M_ij are signed fixed-point coefficients supplied at runtime on
//   `coeff_flat` (row-major: output i, input j at word i*N + j).
//
// FIXED-POINT CONVENTION
//   Coefficients are Q4.12 signed — the SAME format as the PID gains
//   (`pid_gains`, kp/ki) in rtl/feedback/pid_controller.v and INTERFACES §8.
//   A coefficient of 4096 (0x1000) == 1.0. Hence an identity matrix
//   (diagonal = 4096, off-diagonal = 0) reproduces the input exactly even on
//   the NON-bypass path, which the testbench uses as a cross-check.
//   COEFF_FRAC = 12 is the number of fractional bits (the >>> right shift).
//
// GOTCHAS HONOURED (rtl/README.md)
//   * Coefficients are RUNTIME values, so they arrive on an input PORT, never
//     as `parameter signed` (which Vivado synthesises wrong when used in
//     signed arithmetic). N is the only parameter and is purely structural.
//   * The multiply -> accumulate -> shift -> saturate chain is PIPELINED into
//     two register stages (products, then accumulate+shift+saturate) so it can
//     close timing at 125 MHz; the bypass operand is pipelined alongside so the
//     pass-through stays perfectly aligned and bit-exact. Latency = 2 cycles;
//     invisible at the ~100 Hz / 10s-kHz update rates and irrelevant while the
//     block is bypassed and unwired.
//
// This module has NO reset default that can enable the matrix: `y` is only
// driven from the matrix product when the caller drives bypass=0.

module decouple #(
    parameter integer N          = 4,    // channels: [x,y,z,spin]
    parameter integer DATA_W     = 32,   // control word width (matches PID `control`)
    parameter integer COEFF_W    = 16,   // Q4.12 signed coefficient width
    parameter integer COEFF_FRAC = 12    // fractional bits (>>> shift amount)
) (
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          valid_in,     // present a new N-vector of control words
    input  wire                          bypass,       // 1 = pass-through (reset-safe default)

    input  wire [N*DATA_W-1:0]           x_flat,       // N control words in  (signed, packed)
    input  wire [N*N*COEFF_W-1:0]        coeff_flat,   // NxN coeffs, row-major (signed, packed)

    output reg  [N*DATA_W-1:0]           y_flat,       // N control words out (signed, packed)
    output reg                           valid_out
);

    // Product width: DATA_W (signed) * COEFF_W (signed).
    localparam integer PROD_W = DATA_W + COEFF_W;
    // Accumulator holds a sum of N products; grow by clog2(N) guard bits.
    // A fixed generous +6 covers N up to 64 and keeps the code param-simple.
    localparam integer ACC_W  = PROD_W + 6;

    // Signed max/min of a DATA_W word, for saturation on the non-bypass path.
    localparam signed [ACC_W-1:0] SAT_MAX = (({{(ACC_W-1){1'b0}}, 1'b1}) << (DATA_W-1)) - 1;
    localparam signed [ACC_W-1:0] SAT_MIN = -(({{(ACC_W-1){1'b0}}, 1'b1}) << (DATA_W-1));

    genvar gi, gj;

    // -------------------------------------------------------------------------
    // Stage 1: per-(output,input) products p_ij = coeff_ij * x_j, registered.
    //          Also pipeline x through for the bypass path, and valid.
    // -------------------------------------------------------------------------
    reg  signed [PROD_W-1:0] prod_s1 [0:N*N-1];
    reg         [N*DATA_W-1:0] x_s1;
    reg                        bypass_s1;
    reg                        valid_s1;

    // Unpacked, sign-correct views of the inputs.
    wire signed [DATA_W-1:0]  x_w    [0:N-1];
    wire signed [COEFF_W-1:0] coeff_w[0:N*N-1];

    generate
        for (gj = 0; gj < N; gj = gj + 1) begin : g_xw
            assign x_w[gj] = $signed(x_flat[gj*DATA_W +: DATA_W]);
        end
        for (gi = 0; gi < N*N; gi = gi + 1) begin : g_cw
            assign coeff_w[gi] = $signed(coeff_flat[gi*COEFF_W +: COEFF_W]);
        end
    endgenerate

    integer i1, j1;
    always @(posedge clk) begin
        if (!rst_n) begin
            valid_s1  <= 1'b0;
            bypass_s1 <= 1'b1;          // reset-safe: pass-through
            x_s1      <= {N*DATA_W{1'b0}};
            for (i1 = 0; i1 < N*N; i1 = i1 + 1)
                prod_s1[i1] <= {PROD_W{1'b0}};
        end else begin
            valid_s1  <= valid_in;
            bypass_s1 <= bypass;
            x_s1      <= x_flat;
            for (i1 = 0; i1 < N; i1 = i1 + 1)
                for (j1 = 0; j1 < N; j1 = j1 + 1)
                    prod_s1[i1*N + j1] <= coeff_w[i1*N + j1] * x_w[j1];
        end
    end

    // -------------------------------------------------------------------------
    // Stage 2: accumulate the N products per output row, arithmetic-shift by
    //          COEFF_FRAC, saturate to DATA_W; OR select the pipelined bypass
    //          operand for a bit-exact pass-through.
    // -------------------------------------------------------------------------
    wire signed [DATA_W-1:0] x_s1_w [0:N-1];
    generate
        for (gj = 0; gj < N; gj = gj + 1) begin : g_xs1w
            assign x_s1_w[gj] = $signed(x_s1[gj*DATA_W +: DATA_W]);
        end
    endgenerate

    integer i2, j2;
    reg signed [ACC_W-1:0] acc;
    reg signed [ACC_W-1:0] scaled;
    reg signed [DATA_W-1:0] sat;
    always @(posedge clk) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            y_flat    <= {N*DATA_W{1'b0}};
        end else begin
            valid_out <= valid_s1;
            for (i2 = 0; i2 < N; i2 = i2 + 1) begin
                if (bypass_s1) begin
                    // BIT-EXACT pass-through.
                    y_flat[i2*DATA_W +: DATA_W] <= x_s1_w[i2];
                end else begin
                    acc = {ACC_W{1'b0}};
                    for (j2 = 0; j2 < N; j2 = j2 + 1)
                        acc = acc + {{(ACC_W-PROD_W){prod_s1[i2*N + j2][PROD_W-1]}},
                                     prod_s1[i2*N + j2]};
                    scaled = acc >>> COEFF_FRAC;   // arithmetic shift (signed)
                    if      (scaled > SAT_MAX) sat = SAT_MAX[DATA_W-1:0];
                    else if (scaled < SAT_MIN) sat = SAT_MIN[DATA_W-1:0];
                    else                       sat = scaled[DATA_W-1:0];
                    y_flat[i2*DATA_W +: DATA_W] <= sat;
                end
            end
        end
    end

endmodule
