`timescale 1ns / 1ps

// adc_deserial_ll.v — STEMlab 65-16 TI (Z20_ll) serial-LVDS ADC deserializer.
//
// Replaces the 125-14 board's parallel-CMOS ADC bus (rtl/io/adc_interface.v)
// with the 65-16 TI board's 2-wire serial-LVDS-per-channel interface. Modeled
// on the real reference red_pitaya_top_ll.sv (ADC IO block, ~lines 280-340:
// adc_dat_p/n lane assembly -> IBUFDS -> IDELAY/ISERDES -> parallel word).
//
// INTERFACE (matches the framework datapath / WP-ADCFS)
// -----------------------------------------------------
// Emits, per channel, a 16-bit SIGNED sample (`adc_a`, `adc_b`) plus `adc_valid`,
// the 62.5 MS/s sample strobe the framework measurement/DSP blocks consume. This
// is the 16-bit analogue of adc_interface.v's (adc_a, adc_b, adc_valid); the
// 65-16 ADC delivers 16-bit words natively, so no sign_extend_14to16 is needed.
//
// SERIAL FORMAT (this module's assumed framing)
// ---------------------------------------------
//   * Per channel: 2 LVDS data lanes (post-IBUFDS single-ended here).
//       lane[1] = adc_data_i[1] / adc_datb_i[1]  (the "odd"  bit lane)
//       lane[0] = adc_data_i[0] / adc_datb_i[0]  (the "even" bit lane)
//   * adc_dclk : DDR bit clock (250 MHz) -> ISERDESE2 CLK, 2 bits per period.
//   * adc_fclk : frame/word clock (62.5 MHz = adc_dclk/4) -> ISERDESE2 CLKDIV;
//               each rising edge frames one 16-bit sample.
//   * Each lane carries 8 bits/word, MSB first in time. The two lanes are bit
//     interleaved MSB-first into the 16-bit word:
//         adc[2*k+1] <- lane[1] bit k     adc[2*k] <- lane[0] bit k
//     i.e. adc = { l1[7],l0[7], l1[6],l0[6], ... , l1[0],l0[0] }.
//     The output word is two's-complement signed (the ADC serial payload is
//     already signed; unlike the parallel path there is no offset-binary flip).
//
// GATE — NOT sim-validated (Vivado-synthesis + on-hardware bring-up)
// -----------------------------------------------------------------
// The IDELAYE2 tap value that centres each lane's sampling clock in the data
// eye, the real ISERDESE2 Q-ordering / BITSLIP alignment, the exact lane<->bit
// map, and CLK/CLKB/CLKDIV regional-clock (BUFIO/BUFR) phasing are all set at
// Vivado synthesis + on-hardware bring-up against the ADC datasheet and a
// captured frame pattern. In simulation (-DSIM) the behavioral primitives in
// rtl/io/sim_primitives_ll.v stand in for ISERDESE2/IDELAYE2/IDELAYCTRL so the
// deserialize + frame-align datapath can be exercised end-to-end in Icarus.

// ===========================================================================
// Single channel: 2 serial lanes -> one 16-bit signed sample + valid strobe.
// ===========================================================================
module adc_deser_channel #(
    parameter integer IDELAY_VALUE = 0   // per-lane tap; tuned on hardware (GATE)
)(
    input  wire        rst,          // active-high, async
    input  wire        adc_dclk,     // DDR bit clock (ISERDESE2 CLK)
    input  wire        adc_dclk_b,   // ~adc_dclk    (ISERDESE2 CLKB)
    input  wire        adc_fclk,     // frame/word clock (ISERDESE2 CLKDIV)
    input  wire        idelay_rdy,   // IDELAYCTRL RDY (unused in behaviour; real gate)
    input  wire [1:0]  lane_i,       // 2 serial LVDS data lanes (single-ended)

    output reg signed [15:0] adc_sample,
    output reg               adc_valid
);
    // ---- per-lane IDELAYE2 (zero tap in sim; tuned on HW) -----------------
    wire ddly1, ddly0;

    IDELAYE2 #(
        .IDELAY_TYPE  ("VAR_LOAD"),
        .IDELAY_VALUE (IDELAY_VALUE),
        .DELAY_SRC    ("IDATAIN"),
        .SIGNAL_PATTERN ("DATA")
    ) idelay_l1 (
        .CNTVALUEOUT (), .DATAOUT (ddly1),
        .C (adc_fclk), .CE (1'b0), .CINVCTRL (1'b0), .INC (1'b0),
        .LD (1'b0), .LDPIPEEN (1'b0), .REGRST (rst),
        .CNTVALUEIN (5'd0), .DATAIN (1'b0), .IDATAIN (lane_i[1])
    );

    IDELAYE2 #(
        .IDELAY_TYPE  ("VAR_LOAD"),
        .IDELAY_VALUE (IDELAY_VALUE),
        .DELAY_SRC    ("IDATAIN"),
        .SIGNAL_PATTERN ("DATA")
    ) idelay_l0 (
        .CNTVALUEOUT (), .DATAOUT (ddly0),
        .C (adc_fclk), .CE (1'b0), .CINVCTRL (1'b0), .INC (1'b0),
        .LD (1'b0), .LDPIPEEN (1'b0), .REGRST (rst),
        .CNTVALUEIN (5'd0), .DATAIN (1'b0), .IDATAIN (lane_i[0])
    );

    // ---- per-lane ISERDESE2 (DDR, width 8) --------------------------------
    // Q1 = first (oldest) bit of the word, Q8 = last (newest).  q[7]=Q1 ... q[0]=Q8.
    wire [7:0] q1w, q0w;

    ISERDESE2 #(
        .DATA_RATE ("DDR"), .DATA_WIDTH (8),
        .INTERFACE_TYPE ("NETWORKING"), .IOBDELAY ("IFD"),
        .NUM_CE (2), .SERDES_MODE ("MASTER")
    ) iserdes_l1 (
        .Q1 (q1w[7]), .Q2 (q1w[6]), .Q3 (q1w[5]), .Q4 (q1w[4]),
        .Q5 (q1w[3]), .Q6 (q1w[2]), .Q7 (q1w[1]), .Q8 (q1w[0]),
        .O (), .SHIFTOUT1 (), .SHIFTOUT2 (),
        .D (1'b0), .DDLY (ddly1),
        .CLK (adc_dclk), .CLKB (adc_dclk_b), .CLKDIV (adc_fclk), .CLKDIVP (1'b0),
        .OCLK (1'b0), .OCLKB (1'b0), .CE1 (1'b1), .CE2 (1'b1), .RST (rst),
        .BITSLIP (1'b0), .DYNCLKSEL (1'b0), .DYNCLKDIVSEL (1'b0),
        .SHIFTIN1 (1'b0), .SHIFTIN2 (1'b0)
    );

    ISERDESE2 #(
        .DATA_RATE ("DDR"), .DATA_WIDTH (8),
        .INTERFACE_TYPE ("NETWORKING"), .IOBDELAY ("IFD"),
        .NUM_CE (2), .SERDES_MODE ("MASTER")
    ) iserdes_l0 (
        .Q1 (q0w[7]), .Q2 (q0w[6]), .Q3 (q0w[5]), .Q4 (q0w[4]),
        .Q5 (q0w[3]), .Q6 (q0w[2]), .Q7 (q0w[1]), .Q8 (q0w[0]),
        .O (), .SHIFTOUT1 (), .SHIFTOUT2 (),
        .D (1'b0), .DDLY (ddly0),
        .CLK (adc_dclk), .CLKB (adc_dclk_b), .CLKDIV (adc_fclk), .CLKDIVP (1'b0),
        .OCLK (1'b0), .OCLKB (1'b0), .CE1 (1'b1), .CE2 (1'b1), .RST (rst),
        .BITSLIP (1'b0), .DYNCLKSEL (1'b0), .DYNCLKDIVSEL (1'b0),
        .SHIFTIN1 (1'b0), .SHIFTIN2 (1'b0)
    );

    // ---- bit-interleave the two lanes into a 16-bit word ------------------
    // adc[2*k+1] <- lane1 bit k ; adc[2*k] <- lane0 bit k ; MSB first in time.
    wire signed [15:0] samp_w;
    genvar k;
    generate
        for (k = 0; k < 8; k = k + 1) begin : g_interleave
            assign samp_w[2*k+1] = q1w[k];
            assign samp_w[2*k]   = q0w[k];
        end
    endgenerate

    // ---- frame strobe in the bit-clock domain -----------------------------
    // The parallel words update on adc_fclk (ISERDESE2 CLKDIV). Re-time the
    // frame boundary into the adc_dclk domain to emit a clean 1-cycle
    // adc_valid strobe and latch the (now-stable) word.
    reg fclk_d1, fclk_d2;
    always @(posedge adc_dclk or posedge rst) begin
        if (rst) begin
            fclk_d1 <= 1'b0;
            fclk_d2 <= 1'b0;
        end else begin
            fclk_d1 <= adc_fclk;
            fclk_d2 <= fclk_d1;
        end
    end
    wire frame_stb = fclk_d1 & ~fclk_d2;   // rising edge of adc_fclk

    always @(posedge adc_dclk or posedge rst) begin
        if (rst) begin
            adc_sample <= 16'sd0;
            adc_valid  <= 1'b0;
        end else begin
            adc_valid <= frame_stb;
            if (frame_stb)
                adc_sample <= samp_w;
        end
    end
endmodule

// ===========================================================================
// Top: both channels (A on adc_data_i, B on adc_datb_i) + shared IDELAYCTRL.
// ===========================================================================
module adc_deserial_ll #(
    parameter integer IDELAY_VALUE = 0   // per-lane tap; tuned on hardware (GATE)
)(
    input  wire        rst,          // active-high, async
    input  wire        refclk,       // 200 MHz IDELAYCTRL reference (REFCLK)
    input  wire        adc_dclk,     // DDR bit clock
    input  wire        adc_fclk,     // frame/word clock (= sample rate)
    input  wire [1:0]  adc_data_i,   // channel A: 2 serial LVDS lanes
    input  wire [1:0]  adc_datb_i,   // channel B: 2 serial LVDS lanes

    output wire signed [15:0] adc_a, // channel A 16-bit signed sample
    output wire signed [15:0] adc_b, // channel B 16-bit signed sample
    output wire               adc_valid  // 62.5 MS/s sample strobe (both channels)
);
    // CLKB for the ISERDES DDR capture. On hardware this is a BUFIO of the
    // inverted bit clock; the phase relationship is set at bring-up (GATE).
    wire adc_dclk_b = ~adc_dclk;

    // Shared IDELAYCTRL — calibrates the IDELAYE2 taps against refclk.
    wire idelay_rdy;
    IDELAYCTRL idelayctrl_i (
        .RDY    (idelay_rdy),
        .REFCLK (refclk),
        .RST    (rst)
    );

    wire valid_a, valid_b;

    adc_deser_channel #(.IDELAY_VALUE (IDELAY_VALUE)) ch_a (
        .rst (rst), .adc_dclk (adc_dclk), .adc_dclk_b (adc_dclk_b),
        .adc_fclk (adc_fclk), .idelay_rdy (idelay_rdy), .lane_i (adc_data_i),
        .adc_sample (adc_a), .adc_valid (valid_a)
    );

    adc_deser_channel #(.IDELAY_VALUE (IDELAY_VALUE)) ch_b (
        .rst (rst), .adc_dclk (adc_dclk), .adc_dclk_b (adc_dclk_b),
        .adc_fclk (adc_fclk), .idelay_rdy (idelay_rdy), .lane_i (adc_datb_i),
        .adc_sample (adc_b), .adc_valid (valid_b)
    );

    // Both channels share adc_fclk, so their strobes are coincident.
    assign adc_valid = valid_a;

endmodule
