`timescale 1ns / 1ps

// Counter-based LED blinker. Toggles led every half_period cycles when enable=1.
// half_period is sampled live each cycle; changing it on the fly is safe but
// will not finish the current half-cycle early.
module blinker (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire [31:0] half_period,
    output reg         led
);

reg [31:0] cnt;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cnt <= 32'd0;
        led <= 1'b0;
    end else if (!enable) begin
        cnt <= 32'd0;
        led <= 1'b0;
    end else if (cnt + 32'd1 >= half_period) begin
        cnt <= 32'd0;
        led <= ~led;
    end else begin
        cnt <= cnt + 32'd1;
    end
end

endmodule
