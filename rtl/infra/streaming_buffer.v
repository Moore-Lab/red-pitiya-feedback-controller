`timescale 1ns / 1ps

// Circular BRAM buffer of fixed-width records, one record per `write_pulse`
// (typically the measurement block's gate_done). The DAQ reads records via an
// AXI BRAM Controller on the BRAM's other port. This is the framework's
// generalized streaming buffer: `WORDS_PER_RECORD` is a parameter so the same
// core serves any record layout (Board A = 7 words, Board B = 6 words, the
// original spin-controller freq/amp record = 4 words).
//
// RECORD LAYOUT (INTERFACES.md §3):
//   A record is WORDS_PER_RECORD consecutive 32-bit words. The caller supplies
//   the first (WORDS_PER_RECORD-1) *payload* words already packed (16-bit
//   sub-fields packed low/high by the top-level) on `record_data_in`, word 0 in
//   the low bits. The buffer itself appends the final word:
//
//       word[WORDS_PER_RECORD-1] = { sync_flag, write_count[30:0] }   // sample_count
//
//   i.e. the record ends with the monotonic `sample_count`, whose MSB is the
//   multi-board sync flag. The host masks bit[31] out (counts are far below
//   2^31) and uses it to align records across boards.
//
// ADDRESSING:
//   Record `s`, word `w` lives at byte address s*WORDS_PER_RECORD*4 + w*4.
//   The record stride (WORDS_PER_RECORD*4) is not a power of two in general, so
//   we keep a running byte base pointer `rec_base` (advanced by REC_BYTES per
//   record, wrapped with write_ptr) instead of concatenating write_ptr.
//
// WRITE FSM:
//   Each write_pulse runs a small N-cycle FSM (`writing` + `word_idx`) that
//   fires WORDS_PER_RECORD successive 32-bit BRAM writes. Gate intervals are
//   >= ms, so N cycles of the fabric clock fit comfortably between pulses.
//
// FIFO / DROP CONTRACT (INTERFACES.md §3 — writer NEVER stalls):
//   `write_count` (monotonic total written) and `write_ptr` (= write_count mod
//   DEPTH) are exposed. `read_count` is host-written (total the host has
//   consumed). Occupancy = write_count - read_count. When occupancy would reach
//   DEPTH, the next write OVERWRITES the oldest record (write_ptr has wrapped
//   back onto the oldest unread slot) and increments `drop_count`. There is no
//   back-pressure/stall path: the PL always writes on every gate.
//
// MULTI-BOARD SYNC FLAG:
//   `sync_reset` is a 1-cycle pulse from sync_io.v (slave-side recovery of the
//   master's gate boundary). The first record written AFTER a sync_reset has
//   bit[31] of its sample_count word set. If sync_reset and write_pulse arrive
//   on the same cycle (steady state, aligned boards), that record IS the synced
//   one and is flagged. Subsequent records clear the flag until the next
//   sync_reset.
module streaming_buffer #(
    parameter DEPTH_LOG2       = 10,    // 2^10 = 1024 records
    parameter WORDS_PER_RECORD = 4      // 7 = Board A, 6 = Board B, 4 = legacy
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    enable,           // gates the writes
    input  wire                    write_pulse,      // one-cycle pulse to commit a record
    input  wire                    sync_reset,       // multi-board sync edge (tie 0 for standalone)

    // Payload: the first (WORDS_PER_RECORD-1) pre-packed 32-bit words, word 0 in
    // the low bits. The buffer appends the trailing sample_count word itself.
    input  wire [(WORDS_PER_RECORD-1)*32-1:0]                     record_data_in,

    // Host-written total records consumed (drives drop detection).
    input  wire [31:0]             read_count,

    // BRAM port B (Vivado AXI BRAM Controller pattern: byte-write enable)
    output reg  [3:0]              bram_we,
    output reg  [$clog2((1<<DEPTH_LOG2)*WORDS_PER_RECORD*4)-1:0]  bram_addr, // byte address
    output reg  [31:0]             bram_data,

    // Status (exposed via AXI slave)
    output reg  [DEPTH_LOG2-1:0]   write_ptr,        // next record slot (= write_count mod DEPTH)
    output reg  [31:0]             write_count,      // monotonic total records written
    output reg  [31:0]             drop_count        // records overwritten before host read
);

localparam DEPTH     = (1 << DEPTH_LOG2);
localparam REC_BYTES = WORDS_PER_RECORD * 4;                          // record stride, bytes
localparam BYTE_AW   = $clog2((1 << DEPTH_LOG2) * WORDS_PER_RECORD * 4);
localparam WIDX_W    = $clog2(WORDS_PER_RECORD);                      // word index width

// -------------------------------------------------------------------------
// Sync-flag capture. sync_pending is sticky: set by sync_reset, consumed at the
// first write cycle of the record it flags (mirrors the coincident case via the
// `sync_pending | sync_reset` OR at capture time).
// -------------------------------------------------------------------------
reg [(WORDS_PER_RECORD-1)*32-1:0] data_reg;
reg                     sync_flag_reg;
reg                     sync_pending;
reg                     writing;
reg [WIDX_W-1:0]        word_idx;
reg [BYTE_AW-1:0]       rec_base;

always @(posedge clk) begin
    if (!rst_n) begin
        sync_pending <= 1'b0;
    end else if (sync_reset) begin
        sync_pending <= 1'b1;                 // priority: a sync during a write flags the NEXT record
    end else if (writing && (word_idx == {WIDX_W{1'b0}})) begin
        sync_pending <= 1'b0;                 // consumed on the first write cycle
    end
end

always @(posedge clk) begin
    if (!rst_n) begin
        bram_we       <= 4'b0000;
        bram_addr     <= {BYTE_AW{1'b0}};
        bram_data     <= 32'd0;
        write_ptr     <= {DEPTH_LOG2{1'b0}};
        write_count   <= 32'd0;
        drop_count    <= 32'd0;
        rec_base      <= {BYTE_AW{1'b0}};
        writing       <= 1'b0;
        word_idx      <= {WIDX_W{1'b0}};
        data_reg      <= {((WORDS_PER_RECORD-1)*32){1'b0}};
        sync_flag_reg <= 1'b0;
    end else if (!writing) begin
        bram_we <= 4'b0000;
        if (enable && write_pulse) begin
            data_reg      <= record_data_in;
            // OR with live sync_reset so a coincident sync still flags this record.
            sync_flag_reg <= sync_pending | sync_reset;
            word_idx      <= {WIDX_W{1'b0}};
            writing       <= 1'b1;
        end
    end else begin
        // Drive the write of word `word_idx`.
        bram_we   <= 4'b1111;
        bram_addr <= rec_base + {word_idx, 2'b00};   // rec_base + word_idx*4 (zero-extended to BYTE_AW)
        if (word_idx == (WORDS_PER_RECORD-1))
            bram_data <= {sync_flag_reg, write_count[30:0]};                     // trailing sample_count word
        else
            bram_data <= data_reg[word_idx*32 +: 32];

        if (word_idx == (WORDS_PER_RECORD-1)) begin
            // Last word: commit the record.
            writing     <= 1'b0;
            write_count <= write_count + 32'd1;
            write_ptr   <= (write_ptr == (DEPTH-1)) ? {DEPTH_LOG2{1'b0}}
                                                    : write_ptr + 1'b1;          // wraps after DEPTH
            rec_base    <= (write_ptr == (DEPTH-1)) ? {BYTE_AW{1'b0}}
                                                    : rec_base + REC_BYTES;
            // Writer never stalls: when the buffer is full the oldest unread
            // record is overwritten and counted as a drop.
            if ((write_count - read_count) >= DEPTH)
                drop_count <= drop_count + 32'd1;
        end else begin
            word_idx <= word_idx + 1'b1;
        end
    end
end

endmodule
