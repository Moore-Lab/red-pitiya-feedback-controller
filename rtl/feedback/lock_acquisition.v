`timescale 1ns / 1ps

// Two-stage lock acquisition.
//
// State machine:
//   IDLE     (lock_enable = 0): pass `manual_tw` straight through to the NCO,
//                                 keep PID disengaged (locked = 0).
//   RAMPING  (lock_enable = 1 and not yet within capture window):
//                                 on each update_pulse, step base_tw toward
//                                 `target_tw` by ±`ramp_rate` tuning-word units.
//   LOCKED   (lock_enable = 1, error stayed within capture_window for one gate):
//                                 freeze base_tw, assert `locked` so the PID can
//                                 take over the fine correction.
//
// `target_tw` is the NCO tuning word that's expected to produce the setpoint
// frequency at steady state — i.e. what Python computed from
//   target_tw = setpoint_hz * 2^32 / 125e6
//
// `capture_window` is the magnitude of error (in freq-counter counts) at which
// we declare lock. Once locked we don't unlock unless lock_enable is cleared
// and re-asserted (no chatter).
module lock_acquisition (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  lock_enable,
    input  wire                  update_pulse,

    input  wire [31:0]           manual_tw,
    input  wire [31:0]           target_tw,
    input  wire [31:0]           ramp_rate,
    input  wire signed [31:0]    measured_count,
    input  wire signed [31:0]    setpoint_count,
    input  wire [31:0]           capture_window,

    output reg  [31:0]           base_tw,
    output reg                   locked
);

localparam STATE_IDLE    = 2'd0;
localparam STATE_RAMPING = 2'd1;
localparam STATE_LOCKED  = 2'd2;

reg [1:0] state;

// error_abs is registered so the long path from the AXI setpoint register
// (reg18) through the 33-bit subtract + abs combinational logic doesn't reach
// the base_tw clock-enable in a single cycle. One cycle of latency on a state
// machine that updates at gate-rate (~100 Hz) is invisible.
wire signed [32:0] error_signed_comb = setpoint_count - measured_count;
wire        [31:0] error_abs_comb    = error_signed_comb[32] ? (-error_signed_comb[31:0])
                                                              : error_signed_comb[31:0];
reg [31:0] error_abs;
always @(posedge clk) begin
    if (!rst_n) error_abs <= 32'd0;
    else        error_abs <= error_abs_comb;
end

always @(posedge clk) begin
    if (!rst_n) begin
        state   <= STATE_IDLE;
        base_tw <= 32'd0;
        locked  <= 1'b0;
    end else if (!lock_enable) begin
        // Idle: passthrough Python's manually-set tuning word
        state   <= STATE_IDLE;
        base_tw <= manual_tw;
        locked  <= 1'b0;
    end else begin
        case (state)
            STATE_IDLE: begin
                // Lock just enabled — start from wherever Python left base_tw
                base_tw <= manual_tw;
                locked  <= 1'b0;
                state   <= STATE_RAMPING;
            end

            STATE_RAMPING: if (update_pulse) begin
                // Lock declared if EITHER the measurement is in the capture
                // window OR the ramp has reached target_tw — that way PID
                // still gets to engage even when target_tw is mis-calibrated,
                // closing the residual gap from wherever the ramp landed.
                if (error_abs <= capture_window || base_tw == target_tw) begin
                    locked <= 1'b1;
                    state  <= STATE_LOCKED;
                end else if (base_tw < target_tw) begin
                    if ({1'b0, base_tw} + {1'b0, ramp_rate} > 33'hFFFFFFFF)
                        base_tw <= 32'hFFFFFFFF;
                    else if (base_tw + ramp_rate > target_tw)
                        base_tw <= target_tw;
                    else
                        base_tw <= base_tw + ramp_rate;
                end else begin
                    if (ramp_rate > base_tw)
                        base_tw <= 32'd0;
                    else if (base_tw - ramp_rate < target_tw)
                        base_tw <= target_tw;
                    else
                        base_tw <= base_tw - ramp_rate;
                end
            end

            STATE_LOCKED: begin
                // Hold base_tw. PID's correction (added downstream by nco_summer)
                // does the fine-tuning from here.
                locked <= 1'b1;
            end

            default: state <= STATE_IDLE;
        endcase
    end
end

endmodule
