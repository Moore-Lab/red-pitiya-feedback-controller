`timescale 1ns / 1ps

// Numerically Controlled Oscillator (NCO) with sine LUT.
//
// Phase accumulator: 32-bit at 125 MHz.
//   frequency [Hz] = tuning_word * 125e6 / 2^32
//   => tuning_word = freq_Hz * 2^32 / 125e6
//   At full tuning_word = 2^32 - 1, output frequency = 125 MHz (aliased).
//   Useful range: 0 .. ~25 MHz (DAC reconstruction filter rolloff).
//
// Sine LUT: 4096-entry × 14-bit signed (one BRAM18 block).
//
// Amplitude scaling: sine_val * amplitude / 2^14.
//   amplitude = 0x4000 (16384) would give full scale, but max 14-bit unsigned
//   is 0x3FFF (16383) → effectively 1 LSB below full scale.
//
// Total pipeline latency from tuning_word edit to dac_out change: 4 cycles.
module dac_sine #(
    parameter LUT_DEPTH  = 12,   // 2^12 = 4096 entries
    parameter DAC_WIDTH  = 14
)(
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        enable,
    input  wire                        phase_reset,
    input  wire [31:0]                 tuning_word,
    input  wire [DAC_WIDTH-1:0]        amplitude,    // unsigned
    output reg  signed [DAC_WIDTH-1:0] dac_out
);

// -------------------------------------------------------------------------
// Phase accumulator
//
// tuning_word_reg breaks the combinational chain from the AXI registers
// (reg4_nco_tuning, reg20_nco_shift) through nco_summer into the phase
// accumulator's adder. Without this register the path was:
//   reg20 → barrel shift → 64-bit add → saturate → phase_acc adder
// = 23 CARRY4 chains in one cycle, costing ~3.5 ns of slack at 125 MHz.
// One register at this boundary turns it into two well-budgeted paths.
// One cycle of latency from a PID change to the NCO output is invisible
// at the gate-rate update cadence.
// -------------------------------------------------------------------------
reg [31:0] tuning_word_reg;
reg [31:0] phase_acc;

always @(posedge clk) begin
    if (!rst_n) tuning_word_reg <= 32'd0;
    else        tuning_word_reg <= tuning_word;
end

always @(posedge clk) begin
    if (!rst_n)              phase_acc <= 32'd0;
    else if (phase_reset)    phase_acc <= 32'd0;
    else if (enable)         phase_acc <= phase_acc + tuning_word_reg;
end

wire [LUT_DEPTH-1:0] lut_addr = phase_acc[31 -: LUT_DEPTH];

// -------------------------------------------------------------------------
// Sine LUT — precomputed at build time by fpga/scripts/gen_sine_lut.py.
// $sin in an initial block hangs Vivado synthesis on this design size, so we
// load from a hex file instead.
// -------------------------------------------------------------------------
reg signed [DAC_WIDTH-1:0] sine_lut [0:(1<<LUT_DEPTH)-1];

// Search current dir then src/. iverilog finds src/sine_lut.mem when run from fpga/;
// Vivado finds sine_lut.mem when the .mem is added to the project sources.
initial begin
    `ifdef SIM
        $readmemh("src/sine_lut.mem", sine_lut);
    `else
        $readmemh("sine_lut.mem", sine_lut);
    `endif
end

reg signed [DAC_WIDTH-1:0] sine_val;
always @(posedge clk) sine_val <= sine_lut[lut_addr];

// -------------------------------------------------------------------------
// Amplitude scaling: product[27:14] = (sine_val * amplitude) >>> 14
// -------------------------------------------------------------------------
reg signed [2*DAC_WIDTH-1:0] product;
always @(posedge clk) product <= sine_val * $signed({1'b0, amplitude});

always @(posedge clk) begin
    if (!rst_n || !enable) dac_out <= {DAC_WIDTH{1'b0}};
    else                   dac_out <= product[2*DAC_WIDTH-1 -: DAC_WIDTH];
end

endmodule
