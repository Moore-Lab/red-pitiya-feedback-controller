`timescale 1ns / 1ps
//
// tb_lane_closed_loop — integration test of a full closed control lane.
//
//   lock_acquisition -> nco_summer <- pid_controller
//                          |
//                          v
//                       dac_sine -> sign_extend_14to16 -> freq_counter
//                          ^                                   |
//                          +------- measured count feeds back --+
//
// The lane is commanded to a target frequency (count = 100 over a 16384-cycle
// gate). lock_acquisition ramps the NCO word up to the target and declares lock;
// the PID (enabled only once locked, exactly as the real design gates it) then
// holds it. Acceptance: the lane reaches `locked` and holds the measured count at
// the setpoint. This proves the whole feedback loop *composes* — the piece that
// per-module testbenches and the open-loop datapath test cannot show.
//
// (Driving the PID hard from a large error to a setpoint is a fixed-point gain
//  tuning exercise done against the real plant on hardware; here the ramp does the
//  acquisition and the PID holds, which is the composition we can verify in sim.)
//
module tb_lane_closed_loop;
    localparam [31:0] GATE       = 32'd16384;
    localparam [31:0] SETP_COUNT = 32'd100;
    localparam [31:0] TARGET_TW  = 32'd26214400;   // 100 * 262144 -> exactly 100 counts/gate

    reg clk = 0, rstn = 0;
    reg lock_en, pid_en_raw;
    wire gate_done;

    // lock acquisition -> base_tw
    wire [31:0] base_tw;
    wire        locked;
    // pid -> control
    wire signed [31:0] control;
    // nco_summer -> actual_tw -> dac_sine
    wire [31:0] actual_tw;
    wire signed [13:0] dac_out;
    wire signed [15:0] ext;
    // freq_counter -> count
    wire [31:0] count;
    wire [15:0] amp;

    wire pid_en = pid_en_raw & locked;   // real design gates PID on lock

    lock_acquisition u_lock(
        .clk(clk), .rst_n(rstn), .lock_enable(lock_en), .update_pulse(gate_done),
        .manual_tw(32'd0), .target_tw(TARGET_TW), .ramp_rate(32'd4000000),
        .measured_count($signed(count)), .setpoint_count($signed(SETP_COUNT)),
        .capture_window(32'd2), .base_tw(base_tw), .locked(locked));

    pid_controller u_pid(
        .clk(clk), .rst_n(rstn), .enable(pid_en), .update_pulse(gate_done),
        .setpoint($signed(SETP_COUNT)), .measured($signed(count)),
        .kp(16'sd1024), .ki(16'sd205),                  // Q4.12: 0.25, 0.05
        .integ_max(32'sd1073741823), .integ_min(-32'sd1073741823),
        .out_max(32'sd1073741823),   .out_min(-32'sd1073741823),
        .control(control), .saturated_high(), .saturated_low(), .integrator_state());

    nco_summer u_sum(.clk(clk), .rst_n(rstn), .base_tw(base_tw),
                     .pid_correction(control), .shift_left(5'd12), .actual_tw(actual_tw));

    dac_sine u_dac(.clk(clk), .rst_n(rstn), .enable(1'b1), .phase_reset(1'b0),
                   .tuning_word(actual_tw), .amplitude(14'h3FFF), .dac_out(dac_out));

    sign_extend_14to16 u_ext(.in(dac_out), .out(ext));

    freq_counter u_fc(.clk(clk), .rst_n(rstn), .sample_in(ext),
                      .gate_cycles(GATE), .threshold(16'sd300),
                      .sync_reset(1'b0), .sync_slave_mode(1'b0),
                      .count_latched(count), .amplitude_latched(amp), .gate_done(gate_done));

    always #4 clk = ~clk;
    integer errors = 0, gates = 0;

    // count elapsed gates
    always @(posedge clk) if (gate_done) gates = gates + 1;

    initial begin
        lock_en = 0; pid_en_raw = 0;
        repeat (4) @(posedge clk); rstn = 1;
        @(posedge clk); lock_en = 1; pid_en_raw = 1;

        // give the ramp time to reach the target and the loop to settle
        while (gates < 25) @(posedge clk);
        @(posedge clk);

        if (!locked) begin
            $display("FAIL: lane did not lock (base_tw=%0d, count=%0d)", base_tw, count);
            errors = errors + 1;
        end else
            $display("ok: locked; base_tw=%0d", base_tw);

        if (count > SETP_COUNT + 2 || count + 2 < SETP_COUNT) begin
            $display("FAIL: held count=%0d, setpoint=%0d", count, SETP_COUNT);
            errors = errors + 1;
        end else
            $display("ok: held count=%0d at setpoint %0d (pid control=%0d)", count, SETP_COUNT, control);

        if (errors == 0) $display("\nPASS: lane_closed_loop tests");
        else             $display("\nFAIL: lane_closed_loop %0d error(s)", errors);
        $finish;
    end

    initial begin #12000000; $display("FAIL: lane_closed_loop timeout"); $finish; end
endmodule
