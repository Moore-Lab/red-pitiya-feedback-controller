`timescale 1ns / 1ps
//
// tb_lane_datapath — integration test of a control lane's forward datapath.
//
// Wires the real reusable modules exactly as a design (and the WP-6 block-design
// generator) would compose them:
//
//   nco_summer -> dac_sine -> sign_extend_14to16 -> freq_counter
//
// and confirms the measured zero-crossing count matches the commanded NCO tuning
// word: count = tuning_word * gate_cycles / 2^32 (one count per period). This
// verifies the module composition (port widths, gate timing, the 14->16 signed
// adapter) at RTL — the thing per-module testbenches can't catch — and de-risks
// the hardware bring-up, where the same path becomes DAC -> (optics) -> ADC.
//
// gate = 16384 cycles, so tuning_word / 262144 = expected count.
//
module tb_lane_datapath;
    localparam [31:0] GATE = 32'd16384;

    reg clk = 0, rstn = 0;
    reg  [31:0] base_tw;
    reg  signed [31:0] pid_corr;
    reg  [4:0]  shift;
    wire [31:0] actual_tw;
    reg  dac_en, phase_rst;
    wire signed [13:0] dac_out;
    wire signed [15:0] ext;
    reg  signed [15:0] threshold;
    wire [31:0] count;
    wire [15:0] amp;
    wire gate_done;

    nco_summer u_sum(.clk(clk), .rst_n(rstn), .base_tw(base_tw),
                     .pid_correction(pid_corr), .shift_left(shift), .actual_tw(actual_tw));

    dac_sine u_dac(.clk(clk), .rst_n(rstn), .enable(dac_en), .phase_reset(phase_rst),
                   .tuning_word(actual_tw), .amplitude(14'h3FFF), .dac_out(dac_out));

    sign_extend_14to16 u_ext(.in(dac_out), .out(ext));

    freq_counter u_fc(.clk(clk), .rst_n(rstn), .sample_in(ext),
                      .gate_cycles(GATE), .threshold(threshold),
                      .sync_reset(1'b0), .sync_slave_mode(1'b0),
                      .count_latched(count), .amplitude_latched(amp), .gate_done(gate_done));

    always #4 clk = ~clk;
    integer errors = 0;

    task wait_gates(input integer n);
        integer s; begin
            s = 0;
            while (s < n) begin @(posedge clk); if (gate_done) s = s + 1; end
        end
    endtask

    // set a tuning word, let a full clean gate elapse, check the measured count
    task measure_tw(input [31:0] tw, input [31:0] exp);
        begin
            base_tw = tw;
            wait_gates(2);           // discard the transition gate, measure the next
            @(posedge clk);
            if (count > exp + 2 || count + 2 < exp) begin
                $display("FAIL: tw=%0d -> count=%0d, expected ~%0d", tw, count, exp);
                errors = errors + 1;
            end else
                $display("ok: tw=%0d -> count=%0d (exp ~%0d)", tw, count, exp);
        end
    endtask

    initial begin
        base_tw = 0; pid_corr = 0; shift = 0; dac_en = 0; phase_rst = 1; threshold = 16'sd300;
        repeat (4) @(posedge clk); rstn = 1;
        @(posedge clk); dac_en = 1; phase_rst = 0;

        measure_tw(32'd13107200, 32'd50);    // 50 counts / gate
        measure_tw(32'd26214400, 32'd100);   // 100 counts / gate
        measure_tw(32'd39321600, 32'd150);   // 150 counts / gate

        if (amp < 16'd7500) begin
            $display("FAIL: amplitude_latched=%0d implausibly low (want ~8190)", amp);
            errors = errors + 1;
        end else
            $display("ok: amplitude_latched=%0d", amp);

        if (errors == 0) $display("\nPASS: lane_datapath tests");
        else             $display("\nFAIL: lane_datapath %0d error(s)", errors);
        $finish;
    end

    initial begin #6000000; $display("FAIL: lane_datapath timeout"); $finish; end
endmodule
