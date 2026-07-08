`timescale 1ns / 1ps

// Circular buffer of (freq_raw, freq_dec, amp_raw, amp_dec) records, one per
// `write_pulse` (typically the freq_counter gate_done). DAQ reads records via
// AXI BRAM Controller on the BRAM's other port.
//
// Each record is 4 × 32-bit words stored at byte offsets {0, 4, 8, 12} from
// the record's base address `write_ptr * 16`. write_ptr wraps after DEPTH
// records (DEPTH = 2^DEPTH_LOG2). A monotonic `sample_count` lets the DAQ
// detect overruns (records dropped to overwrite).
//
// On each write_pulse we run a tiny 4-cycle state machine that fires four
// 32-bit BRAM writes in succession. Gate intervals are ≥ ms, so 4 cycles of
// PL clock fit comfortably between pulses.
//
// Multi-board trigger-sync flag:
//   sync_reset is a 1-cycle pulse from sync_io.v (the slave-side recovery of
//   the master's gate-boundary pulse). The first record written AFTER a
//   sync_reset has its sync flag set, encoded as bit [31] of the freq_raw
//   word. The host PC masks that bit out when interpreting freq_raw (counts
//   are well below 2^31 in practice — 6 MHz × 10 ms gate = 60 000) and uses
//   it to align records across boards. Subsequent records have bit [31] = 0
//   until the next sync_reset.
//
//   If sync_reset and write_pulse arrive on the same cycle (the steady-state
//   when boards are already aligned), the record being written this cycle
//   IS the freshly-synced one and is flagged.
module streaming_buffer #(
    parameter DEPTH_LOG2 = 10           // 2^10 = 1024 records, 16 KB BRAM
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    enable,           // gates the writes
    input  wire                    write_pulse,      // one-cycle pulse to commit a record
    input  wire                    sync_reset,       // multi-board sync edge (tie 0 for standalone)

    input  wire [31:0]             freq_raw_in,
    input  wire [31:0]             freq_dec_in,
    input  wire [15:0]             amp_raw_in,
    input  wire [15:0]             amp_dec_in,

    // BRAM port B (Vivado AXI BRAM Controller pattern: byte-write enable)
    output reg  [3:0]              bram_we,
    output reg  [DEPTH_LOG2+3:0]   bram_addr,        // byte address
    output reg  [31:0]             bram_data,

    // Status (exposed via AXI slave)
    output reg  [DEPTH_LOG2-1:0]   write_ptr,        // next record slot
    output reg  [31:0]             sample_count      // monotonic total writes
);

localparam IDLE         = 3'd0;
localparam W_FREQ_RAW   = 3'd1;
localparam W_FREQ_DEC   = 3'd2;
localparam W_AMP_RAW    = 3'd3;
localparam W_AMP_DEC    = 3'd4;

reg [2:0] state;
reg [31:0] freq_raw_reg, freq_dec_reg;
reg [15:0] amp_raw_reg,  amp_dec_reg;
reg        sync_flag_reg;   // captured at IDLE → W_FREQ_RAW transition

// sync_pending is sticky: set by sync_reset, cleared one cycle after the
// record starts (in W_FREQ_RAW). If sync_reset and write_pulse coincide,
// the new record is still flagged (via OR with sync_reset at capture time).
reg sync_pending;
always @(posedge clk) begin
    if (!rst_n) begin
        sync_pending <= 1'b0;
    end else if (sync_reset) begin
        sync_pending <= 1'b1;
    end else if (state == W_FREQ_RAW) begin
        sync_pending <= 1'b0;
    end
end

always @(posedge clk) begin
    if (!rst_n) begin
        state         <= IDLE;
        bram_we       <= 4'b0000;
        bram_addr     <= {(DEPTH_LOG2+4){1'b0}};
        bram_data     <= 32'd0;
        write_ptr     <= {DEPTH_LOG2{1'b0}};
        sample_count  <= 32'd0;
        freq_raw_reg  <= 32'd0;
        freq_dec_reg  <= 32'd0;
        amp_raw_reg   <= 16'd0;
        amp_dec_reg   <= 16'd0;
        sync_flag_reg <= 1'b0;
    end else begin
        case (state)
            IDLE: begin
                bram_we <= 4'b0000;
                if (enable && write_pulse) begin
                    freq_raw_reg  <= freq_raw_in;
                    freq_dec_reg  <= freq_dec_in;
                    amp_raw_reg   <= amp_raw_in;
                    amp_dec_reg   <= amp_dec_in;
                    // OR with live sync_reset so a coincident sync still flags
                    // this record (NBA semantics would otherwise miss it).
                    sync_flag_reg <= sync_pending | sync_reset;
                    state         <= W_FREQ_RAW;
                end
            end

            W_FREQ_RAW: begin
                bram_we   <= 4'b1111;
                bram_addr <= {write_ptr, 4'b0000};
                // High bit = sync flag; low 31 bits = freq_raw count.
                bram_data <= {sync_flag_reg, freq_raw_reg[30:0]};
                state     <= W_FREQ_DEC;
            end

            W_FREQ_DEC: begin
                bram_addr <= {write_ptr, 4'b0100};
                bram_data <= freq_dec_reg;
                state     <= W_AMP_RAW;
            end

            W_AMP_RAW: begin
                bram_addr <= {write_ptr, 4'b1000};
                bram_data <= {16'd0, amp_raw_reg};
                state     <= W_AMP_DEC;
            end

            W_AMP_DEC: begin
                bram_addr    <= {write_ptr, 4'b1100};
                bram_data    <= {16'd0, amp_dec_reg};
                write_ptr    <= write_ptr + 1'b1;     // wraps after DEPTH
                sample_count <= sample_count + 1'b1;
                state        <= IDLE;
            end

            default: state <= IDLE;
        endcase
    end
end

endmodule
