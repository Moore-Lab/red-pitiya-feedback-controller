`timescale 1ns / 1ps

// Multi-board trigger synchroniser ("Path A").
//
// Transports a 1-cycle pulse from the master board's freq_counter gate
// boundary to the slave board's freq_counter / streaming_buffer over one
// differential pair on the Gen-2 Daisy_IO (S1/S2 SATA) connector. This
// retargets the original-gen daisy link (verified on the Zynq-7010 STEMlab
// 125-14) to the STEMlab 65-16 TI (Gen 2, Z20_ll board, xc7z020clg400-1).
// Sample clocks are NOT synchronised — each board still runs on its own
// crystal. Only the gate window boundary is aligned, which is what the
// host-PC coupling layer needs to align records by index across boards.
//
// Retarget note (Gen 1 → Gen 2 / Z20_ll): only the PHYSICAL layer changes —
// the pin LOCs and the differential I/O standard. The authoritative 65-16 TI
// (Z20_ll) daisy connector exposes TWO output pairs and TWO input pairs:
//
//     daisy_p_o[0]/n_o[0]  V6/W6   DAISY_IO0   (output pair 0)
//     daisy_p_o[1]/n_o[1]  U7/V7   DAISY_IO1   (output pair 1)
//     daisy_p_i[0]/n_i[0]  T5/U5   DAISY_IO2   (input  pair 0)
//     daisy_p_i[1]/n_i[1]  T9/U10  DAISY_IO3   (input  pair 1)
//
// so the port declarations below are the [1:0] two-pair buses that the board
// physically presents (see constraints/red_pitaya.xdc). The trigger uses ONE
// pair in each direction — pair index [0] (DAISY_IO0 out, DAISY_IO2 in). Pair
// index [1] is RESERVED (in the stock Red Pitaya convention it is the daisy
// clock-forward pair; this design forwards no sample clock, so it is idled on
// the TX side and left unused on the RX side). The 2-FF ASYNC_REG CDC, the
// edge detector, and the master/slave/retransmit distribution below are
// UNCHANGED (bench-verified) and the port-level interface (names + widths) is
// stable so WP-BD-A/B wire the daisy buses unchanged.
//
// Modes (gated by reg27_sync_control bits):
//   sync_master_enable      drive DAISY-OUT from local master_pulse
//                           (typically freq_counter.gate_done on the master)
//   sync_slave_enable       use the synchronised + edge-detected DAISY-IN
//                           pulse as sync_reset
//   sync_retransmit_enable  forward the received pulse to DAISY-OUT (for
//                           daisy-chained 3+ board configurations)
//
// Default (all bits 0): functionally invisible. master_pulse is ignored;
// DAISY-IN is buffered but never drives sync_reset; DAISY-OUT idles low.
//
// Slave-side pipeline:
//   IBUFDS → ff1 (ASYNC_REG) → ff2 (ASYNC_REG) → ff3 → edge detect → sync_rx_pulse
//   sync_reset = sync_slave_enable & sync_rx_pulse
//
// Caller responsibility: don't enable master and retransmit simultaneously
// (they would OR together onto the output line).
//
// Compile with `-DSIM` to swap IBUFDS / OBUFDS for plain wires (iverilog has
// no behavioural model for those Xilinx primitives). In SIM the single-bit
// testbench binds its scalar daisy nets to bit [0] of each bus (Verilog
// low-bit port coercion) — the trigger pair — so the verified behaviour is
// exercised unchanged.
module sync_io (
    input  wire        clk,
    input  wire        rst_n,

    // Control (from reg27)
    input  wire        sync_master_enable,
    input  wire        sync_slave_enable,
    input  wire        sync_retransmit_enable,

    // Master-side input — typically freq_counter.gate_done
    input  wire        master_pulse,

    // Daisy_IO differential pin buses (to top-level ports / XDC).
    // Two TX pairs + two RX pairs; the trigger uses pair index [0].
    output wire [1:0]  daisy_p_o,
    output wire [1:0]  daisy_n_o,
    input  wire [1:0]  daisy_p_i,
    input  wire [1:0]  daisy_n_i,

    // Slave-side output — 1-cycle pulse on local clk
    output wire        sync_reset
);

// --- DAISY-IN: differential receive (trigger pair, index [0]) ---
// The Daisy_IO class on the Z20_ll board is 1V8 differential (DIFF_SSTL18_I —
// the same class the board file assigns to the ADC data/clock diff inputs).
// Native LVDS is NOT usable on this HR bank: 7-series HR banks only offer
// LVDS_25 (VCCO = 2.5 V for the output buffer), which conflicts with the 1.8 V
// daisy bank VCCO and would fail DRC. Keep the IBUFDS/OBUFDS IOSTANDARD here in
// step with constraints/red_pitaya.xdc.
wire daisy_rx;
`ifdef SIM
    // Sim: drive single-ended from the trigger pair's P line. The scalar
    // testbench net binds to daisy_p_i[0]; daisy_n_i / pair [1] are unused.
    assign daisy_rx = daisy_p_i[0];
`else
    IBUFDS #(
        .IBUF_LOW_PWR ("FALSE"),
        .IOSTANDARD   ("DIFF_SSTL18_I")
    ) ibufds_daisy (
        .I  (daisy_p_i[0]),
        .IB (daisy_n_i[0]),
        .O  (daisy_rx)
    );
    // Pair index [1] (daisy_p_i[1]/daisy_n_i[1], DAISY_IO3) is reserved (the
    // stock daisy-clock-in pair) and is intentionally not buffered here — this
    // design does not receive a forwarded sample clock. The DRC harness
    // (fpga/drc_gen2.tcl) buffers it so the constrained port stays legal.
`endif

// --- 2-FF synchroniser (Vivado picks up ASYNC_REG for timing-aware placement) ---
(* ASYNC_REG = "TRUE" *) reg sync_ff1;
(* ASYNC_REG = "TRUE" *) reg sync_ff2;
reg sync_ff3;   // edge-detect history

always @(posedge clk) begin
    if (!rst_n) begin
        sync_ff1 <= 1'b0;
        sync_ff2 <= 1'b0;
        sync_ff3 <= 1'b0;
    end else begin
        sync_ff1 <= daisy_rx;
        sync_ff2 <= sync_ff1;
        sync_ff3 <= sync_ff2;
    end
end

// Rising-edge of the synchronised input — exactly 1 cycle wide.
wire sync_rx_pulse = sync_ff2 & ~sync_ff3;

// --- Slave-side sync_reset output ---
assign sync_reset = sync_slave_enable & sync_rx_pulse;

// --- DAISY-OUT driver (trigger pair, index [0]) ---
// Master mode forwards the local master_pulse; retransmit mode forwards the
// resynchronised received pulse. With both bits cleared the output idles low.
wire daisy_tx = (sync_master_enable     & master_pulse)
              | (sync_retransmit_enable & sync_rx_pulse);

`ifdef SIM
    // Trigger pair [0] carries daisy_tx; the scalar testbench net binds here.
    assign daisy_p_o[0] = daisy_tx;
    assign daisy_n_o[0] = ~daisy_tx;
    // Reserved pair [1] idles.
    assign daisy_p_o[1] = 1'b0;
    assign daisy_n_o[1] = 1'b1;
`else
    OBUFDS #(
        .IOSTANDARD ("DIFF_SSTL18_I"),
        .SLEW       ("SLOW")
    ) obufds_daisy (
        .I  (daisy_tx),
        .O  (daisy_p_o[0]),
        .OB (daisy_n_o[0])
    );
    // Reserved pair [1] (DAISY_IO1, stock daisy-clock-out): idled low so the
    // constrained output stays driven/legal. This design forwards no clock.
    OBUFDS #(
        .IOSTANDARD ("DIFF_SSTL18_I"),
        .SLEW       ("SLOW")
    ) obufds_daisy_rsvd (
        .I  (1'b0),
        .O  (daisy_p_o[1]),
        .OB (daisy_n_o[1])
    );
`endif

endmodule
