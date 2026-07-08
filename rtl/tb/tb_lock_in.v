`timescale 1ns / 1ps
//
// tb_lock_in — self-checking testbench for the I/Q lock-in demodulator.
//
// Injects a tone (built from the same sine LUT) at TW_SIG. With the reference at
// TW_SIG (matched) the demodulated magnitude is large; with the reference at 3*TW_SIG
// (out of band) and with a DC input it is strongly rejected.
//
// gate=4096 samples; TW_SIG = 2^32/256 -> exactly 16 whole cycles per gate, so the
// out-of-band and DC correlations integrate to ~0.
//
module tb_lock_in;
    localparam GATE = 4096;
    localparam [31:0] TW_SIG  = 32'h0100_0000;   // 16 cycles / 4096 samples
    localparam [31:0] TW_OFF  = 32'h0300_0000;   // 48 cycles / gate (out of band)

    reg clk = 0, rstn = 0;
    reg signed [15:0] adc;
    reg [31:0] ref_tw;
    wire signed [31:0] error_count;
    wire [15:0] amplitude;
    wire gate_done;
    wire signed [31:0] i_out, q_out;

    lock_in dut(.clk(clk), .rst_n(rstn), .adc_sample(adc),
                .gate_cycles(GATE), .threshold(16'd0), .ref_tuning_word(ref_tw),
                .error_count(error_count), .amplitude(amplitude), .gate_done(gate_done),
                .i_out(i_out), .q_out(q_out));

    always #4 clk = ~clk;

    // signal-source NCO (same LUT as the DUT)
    reg [31:0] sig_phase = 0;
    reg signed [13:0] siglut [0:4095];
    initial $readmemh("sine_lut.mem", siglut);
    reg drive_tone = 1'b1;
    always @(posedge clk) begin
        sig_phase <= sig_phase + TW_SIG;
        adc <= drive_tone ? {{2{siglut[sig_phase[31:20]][13]}}, siglut[sig_phase[31:20]]}
                          : 16'sd4000;   // DC when tone disabled
    end

    integer errors = 0;

    // wait for `n` completed gates and return the latched magnitude
    task capture_mag(output [31:0] mag);
        integer seen; begin
            seen = 0;
            while (seen < 2) begin
                @(posedge clk);
                if (gate_done) seen = seen + 1;
            end
            @(posedge clk);
            mag = error_count;
        end
    endtask

    reg [31:0] mag_matched, mag_offband, mag_dc;

    initial begin
        adc = 0; ref_tw = TW_SIG; drive_tone = 1;
        repeat (4) @(posedge clk); rstn = 1;

        // matched reference -> large magnitude
        ref_tw = TW_SIG; drive_tone = 1;
        capture_mag(mag_matched);
        $display("matched   magnitude = %0d", mag_matched);

        // out-of-band reference -> rejected
        ref_tw = TW_OFF; drive_tone = 1;
        capture_mag(mag_offband);
        $display("off-band  magnitude = %0d", mag_offband);

        // DC input, matched reference -> rejected (sum of sine over whole cycles ~ 0)
        ref_tw = TW_SIG; drive_tone = 0;
        capture_mag(mag_dc);
        $display("dc-input  magnitude = %0d", mag_dc);

        if (!(mag_matched > 8 * mag_offband)) begin
            $display("FAIL: in-band not >> off-band (%0d vs %0d)", mag_matched, mag_offband);
            errors = errors + 1;
        end
        if (!(mag_matched > 8 * mag_dc)) begin
            $display("FAIL: in-band not >> dc (%0d vs %0d)", mag_matched, mag_dc);
            errors = errors + 1;
        end
        if (mag_matched < 1000) begin
            $display("FAIL: in-band magnitude implausibly small (%0d)", mag_matched);
            errors = errors + 1;
        end

        if (errors == 0) $display("\nPASS: lock_in tests");
        else             $display("\nFAIL: lock_in %0d error(s)", errors);
        $finish;
    end

    initial begin #2000000; $display("FAIL: lock_in timeout"); $finish; end
endmodule
