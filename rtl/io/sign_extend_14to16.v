`timescale 1ns / 1ps

// Sign-extend a 14-bit signed value to 16 bits.
//
// Vivado IPI does NOT preserve signedness when connecting different-width
// signals between cells (it zero-extends, which breaks negative values).
// Instantiate this between a 14-bit signed source and a 16-bit signed sink.
module sign_extend_14to16 (
    input  wire signed [13:0] in,
    output wire signed [15:0] out
);
    assign out = {{2{in[13]}}, in};
endmodule
