`timescale 1ns / 1ps

// 4-stage CIC decimator (Hogenauer architecture), M=1.
//
// Runs at the input rate (125 MHz). out_valid pulses once every R input
// cycles. The internal accumulator grows by ceil(log2(R^N)) bits to prevent
// overflow; the output is truncated back to OUT_WIDTH bits.
//
// DC gain after truncation: R^N / 2^(GROWTH + IN_WIDTH - OUT_WIDTH).
// For R=10, N=4, IN_WIDTH=14, OUT_WIDTH=16: gain ≈ 10^4 / 2^12 ≈ 2.44×.
// Decimated rate = ADC_FS / R; useful passband ≈ 3.75 MHz (at 125 MS/s) with the
// CIC+FIR compensator targeting 60 % of decimated Nyquist.
//
// ADC_FS vs FABRIC_CLK (WP-ADCFS)
// -------------------------------
// The integrators run in the fabric domain but only ingest a fresh input on the
// ADC-sample strobe (ADC_FS; 62.5 MS/s on 65-16 TI => a valid strobe every OTHER
// fabric cycle). Decimation counts R *ADC samples* (not fabric cycles), so the
// decimated rate is ADC_FS / R and the sinc^4 droop shape (a function of R and N
// only) is unchanged — the comp_fir coefficients do not need regenerating for a
// different ADC_FS as long as R and N are unchanged. STROBE_DIV is derived from the
// build-time ADC_FS / FABRIC_CLK defines:
//     STROBE_DIV = FABRIC_CLK / ADC_FS   (integer, clamped >= 1)
// DEFAULT (ADC_FS == FABRIC_CLK == 125e6) => STROBE_DIV = 1 => a strobe every cycle
// => integrate/decimate every cycle => bit-identical to the original input-rate path.
`ifndef ADC_FS
  `define ADC_FS 125000000
`endif
`ifndef FABRIC_CLK
  `define FABRIC_CLK 125000000
`endif
module cic_decimator #(
    parameter R         = 10,
    parameter N         = 4,
    parameter IN_WIDTH  = 14,
    parameter OUT_WIDTH = 16,
    parameter GROWTH    = 14,           // ceil(log2(R^N)) with R=10, N=4
    // Fabric-cycles per ADC sample. Default 1 (ingest every cycle).
    parameter integer STROBE_DIV = ((`FABRIC_CLK / `ADC_FS) < 1)
                                       ? 1 : (`FABRIC_CLK / `ADC_FS)
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire signed [IN_WIDTH-1:0]    in_sample,
    output reg  signed [OUT_WIDTH-1:0]   out_sample,
    output reg                           out_valid
);

localparam W = IN_WIDTH + GROWTH;

// -------------------------------------------------------------------------
// ADC-sample strobe: high once every STROBE_DIV fabric cycles. For the default
// STROBE_DIV==1 the compare is (0 >= 0) so stb_cnt stays 0 and adc_stb is high
// every cycle (bit-identical to the original input-rate integrators).
// -------------------------------------------------------------------------
reg  [15:0] stb_cnt;
wire        adc_stb = (stb_cnt == 16'd0);
always @(posedge clk) begin
    if (!rst_n) stb_cnt <= 16'd0;
    else        stb_cnt <= (stb_cnt >= STROBE_DIV - 1) ? 16'd0 : stb_cnt + 16'd1;
end

// -------------------------------------------------------------------------
// Integrators (advance one step per ADC sample)
// -------------------------------------------------------------------------
reg signed [W-1:0] integ [0:N-1];
wire signed [W-1:0] in_ext = {{(W-IN_WIDTH){in_sample[IN_WIDTH-1]}}, in_sample};

integer i;
always @(posedge clk) begin
    if (!rst_n) begin
        for (i = 0; i < N; i = i + 1) integ[i] <= {W{1'b0}};
    end else if (adc_stb) begin
        integ[0] <= integ[0] + in_ext;
        for (i = 1; i < N; i = i + 1)
            integ[i] <= integ[i] + integ[i-1];
    end
end

// -------------------------------------------------------------------------
// Decimation: snap the last integrator's output every R ADC samples
// -------------------------------------------------------------------------
reg [$clog2(R):0]    dec_cnt;
reg                  dec_valid;
reg signed [W-1:0]   dec_value;

always @(posedge clk) begin
    if (!rst_n) begin
        dec_cnt   <= {($clog2(R)+1){1'b0}};
        dec_valid <= 1'b0;
        dec_value <= {W{1'b0}};
    end else if (adc_stb) begin
        if (dec_cnt == R - 1) begin
            dec_cnt   <= {($clog2(R)+1){1'b0}};
            dec_value <= integ[N-1];
            dec_valid <= 1'b1;
        end else begin
            dec_cnt   <= dec_cnt + 1'b1;
            dec_valid <= 1'b0;
        end
    end else begin
        dec_valid <= 1'b0;   // dec_valid pulses only on a strobe cycle
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
