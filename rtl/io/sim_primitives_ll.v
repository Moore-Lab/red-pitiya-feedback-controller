`timescale 1ns / 1ps

// sim_primitives_ll.v — BEHAVIORAL models of the Xilinx 7-series I/O SERDES
// primitives (ISERDESE2, IDELAYE2, IDELAYCTRL) for the STEMlab 65-16 TI
// (Z20_ll) serial-LVDS ADC deserializer (rtl/io/adc_deserial_ll.v).
//
// WHY THIS FILE EXISTS
// --------------------
// Icarus Verilog cannot elaborate the real Xilinx unisim primitives, so the
// deserialize + frame-align *logic* in adc_deserial_ll.v cannot be exercised
// end-to-end in simulation without stand-in models. This file provides just
// enough behaviour to shift a serial LVDS bit stream through the same module
// hierarchy the hardware build uses and recover the parallel word.
//
// COMPILE / SELECTION CONTRACT
// ----------------------------
//   * Icarus (simulation): compile this file WITH -DSIM. It defines modules
//     literally named ISERDESE2 / IDELAYE2 / IDELAYCTRL, so adc_deserial_ll.v's
//     UNCHANGED instantiations bind to these behavioral models.
//   * Vivado (synthesis, GATE): do NOT add this file to the project. The exact
//     same instantiations in adc_deserial_ll.v bind to the real unisim library
//     primitives shipped with Vivado. This is the true hardware path.
//
// GATE — NOT VALIDATED HERE (Vivado-synthesis + on-hardware bring-up)
// ------------------------------------------------------------------
//   * The real ISERDESE2 Q1..Q8 -> serial-bit ordering differs from this model
//     (real Q1 is the most-recently captured bit; here Q1 is documented as the
//     first/oldest bit of the group). Final bit ordering / BITSLIP count is set
//     against the ADC datasheet + captured frame pattern at bring-up.
//   * IDELAYE2 tap value (IDELAY_VALUE) is a passthrough here (0 taps). The real
//     per-lane tap that centres the sampling clock in the data eye is tuned on
//     hardware with IDELAYCTRL calibrated. None of that timing is modelled here.
//   * CLK/CLKB/CLKDIV phase (BUFIO/BUFR regional clocking) is idealised in sim.

// ---------------------------------------------------------------------------
// IDELAYCTRL — behavioral: ready whenever not held in reset.
// ---------------------------------------------------------------------------
module IDELAYCTRL (
    output RDY,
    input  REFCLK,
    input  RST
);
    assign RDY = ~RST;
endmodule

// ---------------------------------------------------------------------------
// IDELAYE2 — behavioral: zero-tap passthrough of the input data (IDATAIN).
// The real tap delay is a hardware bring-up concern (see GATE note above).
// ---------------------------------------------------------------------------
module IDELAYE2 #(
    parameter         IDELAY_TYPE           = "FIXED",
    parameter integer IDELAY_VALUE          = 0,
    parameter         DELAY_SRC             = "IDATAIN",
    parameter         HIGH_PERFORMANCE_MODE = "TRUE",
    parameter         SIGNAL_PATTERN        = "DATA",
    parameter         CINVCTRL_SEL          = "FALSE",
    parameter         PIPE_SEL              = "FALSE",
    parameter real    REFCLK_FREQUENCY      = 200.0
)(
    output [4:0] CNTVALUEOUT,
    output       DATAOUT,
    input        C,
    input        CE,
    input        CINVCTRL,
    input        INC,
    input        LD,
    input        LDPIPEEN,
    input        REGRST,
    input  [4:0] CNTVALUEIN,
    input        DATAIN,
    input        IDATAIN
);
    // Zero-tap passthrough. Sampling-eye centring is done on hardware.
    assign DATAOUT     = IDATAIN;
    assign CNTVALUEOUT = 5'd0;
endmodule

// ---------------------------------------------------------------------------
// ISERDESE2 — behavioral DDR width-8 deserializer (NETWORKING mode).
//
// Samples the delayed data (DDLY) on BOTH edges of CLK (DDR) into a shift
// register, and presents the collected DATA_WIDTH bits as Q1..Q8 latched on
// CLKDIV (the word-rate parallel clock). Framing (which run of 8 bits forms a
// word) is set by the CLKDIV phase, which the deserializer drives from the ADC
// frame clock.
//
// Bit-order convention in THIS model: Q1 = first (oldest) bit of the group,
// Q8 = last (newest). See GATE note for the real-primitive difference.
// ---------------------------------------------------------------------------
module ISERDESE2 #(
    parameter         DATA_RATE         = "DDR",
    parameter integer DATA_WIDTH        = 8,
    parameter         INTERFACE_TYPE    = "NETWORKING",
    parameter         IOBDELAY          = "IFD",
    parameter integer NUM_CE            = 2,
    parameter         SERDES_MODE       = "MASTER",
    parameter         DYN_CLKDIV_INV_EN = "FALSE",
    parameter         DYN_CLK_INV_EN    = "FALSE",
    parameter         OFB_USED          = "FALSE"
)(
    output       Q1, Q2, Q3, Q4, Q5, Q6, Q7, Q8,
    output       O,
    output       SHIFTOUT1, SHIFTOUT2,
    input        D,
    input        DDLY,
    input        CLK,
    input        CLKB,
    input        CLKDIV,
    input        CLKDIVP,
    input        OCLK,
    input        OCLKB,
    input        CE1,
    input        CE2,
    input        RST,
    input        BITSLIP,
    input        DYNCLKSEL,
    input        DYNCLKDIVSEL,
    input        SHIFTIN1,
    input        SHIFTIN2
);
    // Chosen serial source: delayed data when IOBDELAY routes through IDELAY.
    wire samp = (IOBDELAY == "NONE") ? D : DDLY;

    // DDR capture: one bit on each CLK edge. CLKB is the caller-supplied ~CLK,
    // so (posedge CLK or posedge CLKB) fires on both edges of CLK without a
    // multi-driver race on the shift register.
    reg [DATA_WIDTH-1:0] sr;
    always @(posedge CLK or posedge CLKB or posedge RST) begin
        if (RST) sr <= {DATA_WIDTH{1'b0}};
        else     sr <= {sr[DATA_WIDTH-2:0], samp};
    end

    // Latch the collected word on the parallel (word-rate) clock.
    reg [DATA_WIDTH-1:0] word;
    always @(posedge CLKDIV or posedge RST) begin
        if (RST) word <= {DATA_WIDTH{1'b0}};
        else     word <= sr;
    end

    // word[MSB] holds the first (oldest) captured bit -> Q1.
    assign {Q1, Q2, Q3, Q4, Q5, Q6, Q7, Q8} = word;

    // Unused outputs in this model.
    assign O         = 1'b0;
    assign SHIFTOUT1 = 1'b0;
    assign SHIFTOUT2 = 1'b0;
endmodule
