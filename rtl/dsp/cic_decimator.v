`timescale 1ns / 1ps

// 4-stage CIC decimator (Hogenauer architecture), M=1.
//
// Runs at the input rate (125 MHz). out_valid pulses once every R input
// cycles. The internal accumulator grows by ceil(log2(R^N)) bits to prevent
// overflow; the output is truncated back to OUT_WIDTH bits.
//
// DC gain after truncation: R^N / 2^(GROWTH + IN_WIDTH - OUT_WIDTH).
// For R=10, N=4, IN_WIDTH=14, OUT_WIDTH=16: gain ≈ 10^4 / 2^12 ≈ 2.44×.
// Decimated rate = 125 MHz / R = 12.5 MHz; useful passband ≈ 3.75 MHz with the
// CIC+FIR compensator targeting 60 % of decimated Nyquist.
module cic_decimator #(
    parameter R         = 10,
    parameter N         = 4,
    parameter IN_WIDTH  = 14,
    parameter OUT_WIDTH = 16,
    parameter GROWTH    = 14            // ceil(log2(R^N)) with R=10, N=4
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire signed [IN_WIDTH-1:0]    in_sample,
    output reg  signed [OUT_WIDTH-1:0]   out_sample,
    output reg                           out_valid
);

localparam W = IN_WIDTH + GROWTH;

// -------------------------------------------------------------------------
// Integrators (run at input rate)
// -------------------------------------------------------------------------
reg signed [W-1:0] integ [0:N-1];
wire signed [W-1:0] in_ext = {{(W-IN_WIDTH){in_sample[IN_WIDTH-1]}}, in_sample};

integer i;
always @(posedge clk) begin
    if (!rst_n) begin
        for (i = 0; i < N; i = i + 1) integ[i] <= {W{1'b0}};
    end else begin
        integ[0] <= integ[0] + in_ext;
        for (i = 1; i < N; i = i + 1)
            integ[i] <= integ[i] + integ[i-1];
    end
end

// -------------------------------------------------------------------------
// Decimation: snap the last integrator's output every R cycles
// -------------------------------------------------------------------------
reg [$clog2(R):0]    dec_cnt;
reg                  dec_valid;
reg signed [W-1:0]   dec_value;

always @(posedge clk) begin
    if (!rst_n) begin
        dec_cnt   <= {($clog2(R)+1){1'b0}};
        dec_valid <= 1'b0;
        dec_value <= {W{1'b0}};
    end else if (dec_cnt == R - 1) begin
        dec_cnt   <= {($clog2(R)+1){1'b0}};
        dec_value <= integ[N-1];
        dec_valid <= 1'b1;
    end else begin
        dec_cnt   <= dec_cnt + 1'b1;
        dec_valid <= 1'b0;
    end
end

// -------------------------------------------------------------------------
// Combs (run at decimated rate via dec_valid; each stage is registered, so
// there is N decimated cycles of pipeline latency from a fresh dec_value to
// the corresponding out_sample).
// -------------------------------------------------------------------------
reg signed [W-1:0] comb_out   [0:N-1];
reg signed [W-1:0] comb_delay [0:N-1];

always @(posedge clk) begin
    if (!rst_n) begin
        for (i = 0; i < N; i = i + 1) begin
            comb_out[i]   <= {W{1'b0}};
            comb_delay[i] <= {W{1'b0}};
        end
        out_sample <= {OUT_WIDTH{1'b0}};
        out_valid  <= 1'b0;
    end else if (dec_valid) begin
        comb_delay[0] <= dec_value;
        comb_out[0]   <= dec_value - comb_delay[0];
        for (i = 1; i < N; i = i + 1) begin
            comb_delay[i] <= comb_out[i-1];
            comb_out[i]   <= comb_out[i-1] - comb_delay[i];
        end
        out_sample <= comb_out[N-1][W-1 -: OUT_WIDTH];
        out_valid  <= 1'b1;
    end else begin
        out_valid <= 1'b0;
    end
end

endmodule
