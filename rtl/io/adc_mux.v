`timescale 1ns / 1ps

// Single-bit 2:1 mux for an ADC sample stream.
//
// Use case (added 2026-06-19): the raw and decimated freq counters were
// hardwired to ADC channel A so the cross-board characterisation could only
// be done via the FFT capture path. With this mux in front of each freq
// counter's input chain, the host can pick channel A or B via reg28 and
// run the on-PL counter on either intra-board loopback or cross-board
// arrival. Pure combinational; no clock.
module adc_mux (
    input  wire signed [13:0] adc_a,
    input  wire signed [13:0] adc_b,
    input  wire               select,    // 0 = adc_a, 1 = adc_b
    output wire signed [13:0] adc_out
);
    assign adc_out = select ? adc_b : adc_a;
endmodule
