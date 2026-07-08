`timescale 1ns / 1ps

// Fixed-point PI controller with anti-windup (D term omitted intentionally —
// the optical-trap plant is heavily damped, so the noise penalty of a D term
// outweighs its benefit for first lock).
//
// All math in 32-bit signed integers, gains in Q4.12 (so kp/ki/kd = 4096
// corresponds to a floating-point gain of 1.0).
//
// The controller updates once per `update_pulse` (typically driven by the
// freq_counter's `gate_done` so the controller runs at the gate rate).
//
//   error            = setpoint - measured
//   p_term           = (kp * error) >>> 12
//   integral        += (ki * error) >>> 12         // clamped to anti-windup limits
//   raw_output       = p_term + integral
//   output           = raw_output, saturated to [out_min, out_max]
//   saturated        = 1 when the output was clipped (also freezes the integral)
//
// On `enable` = 0, the controller resets internal state and emits 0.
//
// PIPELINING (added 2026-06-19): the arithmetic chain from the AXI-set
// `setpoint` register all the way to `integrator_state_reg` previously had
// 19 logic levels and 9.93 ns of logic delay — over the 8 ns budget at
// 125 MHz. Splitting it into three pipeline stages drops the longest path
// to a single (add + compare + mux). The control output now updates 3
// clock cycles after `update_pulse` rather than 1, which is invisible at
// the ~100 Hz update rate (one update per 1.25M clocks).
//
//   Stage 1 (1 cycle after update_pulse): latch error and gains.
//   Stage 2 (2 cycles): multiplies + slice to get p_term, i_increment.
//   Stage 3 (3 cycles): integrator update + output sum + saturation.
module pid_controller (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  enable,
    input  wire                  update_pulse,

    input  wire signed [31:0]    setpoint,
    input  wire signed [31:0]    measured,
    input  wire signed [15:0]    kp,                  // Q4.12
    input  wire signed [15:0]    ki,                  // Q4.12

    // Anti-windup limits on the integrator state and output clamp.
    input  wire signed [31:0]    integ_max,
    input  wire signed [31:0]    integ_min,
    input  wire signed [31:0]    out_max,
    input  wire signed [31:0]    out_min,

    output reg  signed [31:0]    control,
    output reg                   saturated_high,
    output reg                   saturated_low,
    output reg  signed [31:0]    integrator_state    // exposed for diagnostics
);

// -------------------------------------------------------------------------
// Stage 1: capture error and gains at the update edge.
// Adds 1 cycle of latency. Buys ~3 ns by registering after the AXI register.
// -------------------------------------------------------------------------
reg signed [31:0] error_s1;
reg signed [15:0] kp_s1, ki_s1;
reg               valid_s1;

always @(posedge clk) begin
    if (!rst_n || !enable) begin
        error_s1 <= 32'sd0;
        kp_s1    <= 16'sd0;
        ki_s1    <= 16'sd0;
        valid_s1 <= 1'b0;
    end else begin
        valid_s1 <= update_pulse;
        if (update_pulse) begin
            error_s1 <= setpoint - measured;
            kp_s1    <= kp;
            ki_s1    <= ki;
        end
    end
end

// -------------------------------------------------------------------------
// Stage 2: 32×32 multiplies + Q4.12 slice.
// Vivado will infer DSP48E1s with the M-register enabled (the `*_s2` output
// flops are exactly the DSP's output register). Buys ~2-3 ns by absorbing
// the DSP delay into a dedicated stage.
// -------------------------------------------------------------------------
wire signed [31:0] kp_ext_s1     = {{16{kp_s1[15]}}, kp_s1};
wire signed [31:0] ki_ext_s1     = {{16{ki_s1[15]}}, ki_s1};
wire signed [63:0] kp_err_full_s1 = kp_ext_s1 * error_s1;
wire signed [63:0] ki_err_full_s1 = ki_ext_s1 * error_s1;

reg signed [31:0] p_term_s2;
reg signed [31:0] i_increment_s2;
reg               valid_s2;

always @(posedge clk) begin
    if (!rst_n || !enable) begin
        p_term_s2      <= 32'sd0;
        i_increment_s2 <= 32'sd0;
        valid_s2       <= 1'b0;
    end else begin
        valid_s2 <= valid_s1;
        if (valid_s1) begin
            p_term_s2      <= kp_err_full_s1[43:12];
            i_increment_s2 <= ki_err_full_s1[43:12];
        end
    end
end

// -------------------------------------------------------------------------
// Stage 3: integrator update + output sum + saturation.
// One register-to-register hop with a 33-bit add + a 33-bit compare + a mux.
// Within budget at 125 MHz.
// -------------------------------------------------------------------------
reg signed [32:0] proposed_integral;   // one extra bit so the integrator add never wraps
reg signed [32:0] raw_output;

always @(posedge clk) begin
    if (!rst_n || !enable) begin
        integrator_state <= 32'sd0;
        control          <= 32'sd0;
        saturated_high   <= 1'b0;
        saturated_low    <= 1'b0;
    end else if (valid_s2) begin
        // Anti-windup: freeze the integrator if the *previous* output was
        // saturated in the direction the new increment would push it further.
        if      ((saturated_high && i_increment_s2 > 0) ||
                 (saturated_low  && i_increment_s2 < 0))
            proposed_integral = integrator_state;
        else
            proposed_integral = integrator_state + i_increment_s2;

        // Clamp the integrator state itself.
        if      (proposed_integral > integ_max)
            integrator_state <= integ_max;
        else if (proposed_integral < integ_min)
            integrator_state <= integ_min;
        else
            integrator_state <= proposed_integral[31:0];

        // Output = p_term + OLD integrator_state (matches original semantics:
        // the integrator update lands one pulse later in the output path).
        raw_output = p_term_s2 + integrator_state;

        if (raw_output > out_max) begin
            control        <= out_max;
            saturated_high <= 1'b1;
            saturated_low  <= 1'b0;
        end else if (raw_output < out_min) begin
            control        <= out_min;
            saturated_high <= 1'b0;
            saturated_low  <= 1'b1;
        end else begin
            control        <= raw_output[31:0];
            saturated_high <= 1'b0;
            saturated_low  <= 1'b0;
        end
    end
end

endmodule
