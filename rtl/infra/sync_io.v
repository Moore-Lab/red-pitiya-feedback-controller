`timescale 1ns / 1ps

// Multi-board trigger synchroniser ("Path A").
//
// Transports a 1-cycle pulse from the master board's freq_counter gate
// boundary to the slave board's freq_counter / streaming_buffer over an LVDS
// pair on the DAISY (SATA) connector. Sample clocks are NOT synchronised —
// each board still runs on its own 125 MHz crystal. Only the gate window
// boundary is aligned, which is what the host-PC coupling layer needs to
// align records by index across boards.
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
// no behavioural model for those Xilinx primitives).
module sync_io (
    input  wire        clk,
    input  wire        rst_n,

    // Control (from reg27)
    input  wire        sync_master_enable,
    input  wire        sync_slave_enable,
    input  wire        sync_retransmit_enable,

    // Master-side input — typically freq_counter.gate_done
    input  wire        master_pulse,

    // LVDS pin pair (to top-level ports / XDC)
    output wire        daisy_p_o,
    output wire        daisy_n_o,
    input  wire        daisy_p_i,
    input  wire        daisy_n_i,

    // Slave-side output — 1-cycle pulse on local clk
    output wire        sync_reset
);

// --- DAISY-IN: differential receive ---
// The Red Pitaya DAISY pins are DIFF_HSTL_I_18 in Pavel Demin's canonical
// constraints (cfg/ports.xdc) — same I/O standard as the ADC clock, NOT
// LVDS_25. The brief in docs/multi_board_trigger_sync.md §8 was incorrect
// on this point. The XDC entries in fpga/constraints/red_pitaya.xdc use
// the verified DIFF_HSTL_I_18 standard.
wire daisy_rx;
`ifdef SIM
    // Sim: drive single-ended from daisy_p_i. daisy_n_i is unused.
    assign daisy_rx = daisy_p_i;
`else
    IBUFDS #(
        .IBUF_LOW_PWR ("FALSE"),
        .IOSTANDARD   ("DIFF_HSTL_I_18")
    ) ibufds_daisy (
        .I  (daisy_p_i),
        .IB (daisy_n_i),
        .O  (daisy_rx)
    );
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

// --- DAISY-OUT driver ---
// Master mode forwards the local master_pulse; retransmit mode forwards the
// resynchronised received pulse. With both bits cleared the output idles low.
wire daisy_tx = (sync_master_enable     & master_pulse)
              | (sync_retransmit_enable & sync_rx_pulse);

`ifdef SIM
    assign daisy_p_o = daisy_tx;
    assign daisy_n_o = ~daisy_tx;
`else
    OBUFDS #(
        .IOSTANDARD ("DIFF_HSTL_I_18"),
        .SLEW       ("SLOW")
    ) obufds_daisy (
        .I  (daisy_tx),
        .O  (daisy_p_o),
        .OB (daisy_n_o)
    );
`endif

endmodule
