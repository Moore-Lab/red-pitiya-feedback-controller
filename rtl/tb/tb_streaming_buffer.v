`timescale 1ns / 1ps

// Testbench for the generalized streaming_buffer.v (INTERFACES.md §3).
//
// The DUT is exercised at two record widths — WORDS_PER_RECORD = 7 (Board A) and
// 6 (Board B) — by two independent `sb_scenario` instances. Each scenario asserts:
//   (a) records land at the parameterized width/offsets: (WPR-1) payload words
//       followed by a trailing sample_count word = {sync_flag, write_count[30:0]};
//   (b) an induced overrun makes drop_count == the number of overwritten records
//       (writer never stalls: it overwrites the oldest unread record);
//   (c) advancing read_count frees space and stops further drops;
//   (d) the sync flag (bit[31] of the sample_count word) is set on the first
//       record after a sync_reset — including the coincident sync_reset+write
//       case — and cleared on subsequent records.
//
// The top module aggregates both scenarios' error counts and prints a single
// PASS / FAIL line for run_sims.sh.

// -------------------------------------------------------------------------
// Per-width scenario: self-contained clock, DUT, behavioral BRAM, stimulus.
// -------------------------------------------------------------------------
module sb_scenario #(
    parameter WPR        = 7,       // WORDS_PER_RECORD under test
    parameter DEPTH_LOG2 = 2        // DEPTH = 4 (small, so overrun is quick)
)(
    output reg [31:0] errors,
    output reg        done
);
    localparam DEPTH   = (1 << DEPTH_LOG2);
    localparam BYTE_AW = $clog2(DEPTH * WPR * 4);
    localparam PW_BITS = (WPR-1) * 32;

    reg                    clk = 0;
    reg                    rst_n = 0;
    reg                    enable = 0;
    reg                    write_pulse = 0;
    reg                    sync_reset = 0;
    reg  [PW_BITS-1:0]     rec_in = {PW_BITS{1'b0}};
    reg  [31:0]            read_count = 0;

    wire [3:0]             bram_we;
    wire [BYTE_AW-1:0]     bram_addr;
    wire [31:0]            bram_data;
    wire [DEPTH_LOG2-1:0]  write_ptr;
    wire [31:0]            write_count;
    wire [31:0]            drop_count;

    streaming_buffer #(
        .DEPTH_LOG2      (DEPTH_LOG2),
        .WORDS_PER_RECORD(WPR)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .enable         (enable),
        .write_pulse    (write_pulse),
        .sync_reset     (sync_reset),
        .record_data_in (rec_in),
        .read_count     (read_count),
        .bram_we        (bram_we),
        .bram_addr      (bram_addr),
        .bram_data      (bram_data),
        .write_ptr      (write_ptr),
        .write_count    (write_count),
        .drop_count     (drop_count)
    );

    always #4 clk = ~clk;

    // Behavioral BRAM (word-addressed model of the AXI BRAM Controller port).
    reg [31:0] bram [0:DEPTH*WPR - 1];
    always @(posedge clk) begin
        if (bram_we[0]) bram[bram_addr >> 2] <= bram_data;
    end

    // Deterministic payload word for record `s`, word `w` (bit31 always 0).
    function [31:0] pw(input integer s, input integer w);
        pw = ((s & 32'hFFFF) << 16) | ((w & 32'hFF) << 8) | 32'h5A;
    endfunction

    // Drive one record: payload = pw(s,*); optionally pulse sync_reset either
    // one cycle earlier (do_sync=1, coincident=0) or on the same cycle
    // (do_sync=1, coincident=1).
    integer w;
    task issue(input integer s, input do_sync, input coincident);
        begin
            if (do_sync && !coincident) begin
                @(negedge clk); sync_reset = 1'b1;
                @(negedge clk); sync_reset = 1'b0;
                repeat (2) @(posedge clk);
            end
            @(negedge clk);
            for (w = 0; w < WPR-1; w = w + 1)
                rec_in[w*32 +: 32] = pw(s, w);
            write_pulse = 1'b1;
            if (do_sync && coincident) sync_reset = 1'b1;
            @(negedge clk);
            write_pulse = 1'b0;
            if (do_sync && coincident) sync_reset = 1'b0;
            repeat (WPR + 3) @(posedge clk);   // let the N-cycle write FSM finish
            #1;
        end
    endtask

    // Check the record stored in `slot` holds record `s`'s payload and a
    // trailing sample_count word = {expect_flag, count[30:0]}.
    task check_record(input integer slot, input integer s,
                      input expect_flag, input [30:0] count);
        reg [31:0] expected_sc;
        integer ww;
        begin
            for (ww = 0; ww < WPR-1; ww = ww + 1) begin
                if (bram[slot*WPR + ww] !== pw(s, ww)) begin
                    $display("FAIL[WPR=%0d]: slot %0d word %0d = %h, expected %h",
                             WPR, slot, ww, bram[slot*WPR + ww], pw(s, ww));
                    errors = errors + 1;
                end
            end
            expected_sc = {expect_flag, count};
            if (bram[slot*WPR + (WPR-1)] !== expected_sc) begin
                $display("FAIL[WPR=%0d]: slot %0d sample_count word = %h, expected %h (flag=%0b count=%0d)",
                         WPR, slot, bram[slot*WPR + (WPR-1)], expected_sc, expect_flag, count);
                errors = errors + 1;
            end
        end
    endtask

    task expect_eq(input [31:0] got, input [31:0] exp, input [255:0] name);
        begin
            if (got !== exp) begin
                $display("FAIL[WPR=%0d]: %0s = %0d, expected %0d", WPR, name, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    integer k;
    initial begin
        errors = 0;
        done   = 0;

        repeat (4) @(posedge clk);
        rst_n  = 1;
        @(posedge clk);
        enable = 1;
        read_count = 0;

        // -------- Phase A: width / offsets / write_ptr / monotonic count -----
        issue(0, 0, 0);
        check_record(0, 0, 1'b0, 31'd0);
        expect_eq(write_ptr,   32'd1, "write_ptr after rec0");
        expect_eq(write_count, 32'd1, "write_count after rec0");
        expect_eq(drop_count,  32'd0, "drop_count after rec0");

        issue(1, 0, 0);
        check_record(1, 1, 1'b0, 31'd1);
        expect_eq(write_ptr,   32'd2, "write_ptr after rec1");

        // -------- Disable suppresses writes ---------------------------------
        enable = 0;
        issue(99, 0, 0);
        expect_eq(write_ptr,   32'd2, "write_ptr frozen while disabled");
        expect_eq(write_count, 32'd2, "write_count frozen while disabled");
        enable = 1;

        // -------- Phase B: sync flag ----------------------------------------
        // (d) sync_reset one cycle before the write → that record is flagged.
        issue(2, 1, 0);
        check_record(2, 2, 1'b1, 31'd2);
        // next record, no fresh sync → flag clears.
        issue(3, 0, 0);
        check_record(3, 3, 1'b0, 31'd3);
        // write_count is now 4 (= DEPTH); host drains so we can keep testing.
        read_count = 4;
        // coincident sync_reset + write_pulse → record flagged.
        issue(4, 1, 1);
        check_record(4 % DEPTH, 4, 1'b1, 31'd4);
        // record after the synced one → flag cleared again.
        issue(5, 0, 0);
        check_record(5 % DEPTH, 5, 1'b0, 31'd5);
        expect_eq(drop_count,  32'd0, "no drops yet (host kept up)");

        // -------- Phase C: induced overrun → drop_count == overwritten -------
        // Drain fully, then freeze read_count and overrun the DEPTH slots.
        read_count = write_count;              // = 6, unread = 0
        // Fill exactly DEPTH records: no drops (buffer just becomes full).
        for (k = 6; k < 6 + DEPTH; k = k + 1)
            issue(k, 0, 0);
        expect_eq(drop_count, 32'd0, "no drops filling to exactly DEPTH");
        // Now write 3 more with read_count frozen → 3 oldest overwritten.
        for (k = 6 + DEPTH; k < 6 + DEPTH + 3; k = k + 1)
            issue(k, 0, 0);
        expect_eq(drop_count, 32'd3, "drop_count == number of overwritten records");

        // -------- Phase D: advancing read_count frees space, stops drops -----
        read_count = write_count;              // drained again, unread = 0
        for (k = 6 + DEPTH + 3; k < 6 + DEPTH + 5; k = k + 1)
            issue(k, 0, 0);
        expect_eq(drop_count, 32'd3, "drop_count unchanged after freeing space");
        // Last written record's payload still lands correctly (wrapped slot).
        check_record((6 + DEPTH + 4) % DEPTH, 6 + DEPTH + 4, 1'b0,
                     (6 + DEPTH + 4));

        done = 1;
    end

    // Per-scenario watchdog.
    initial begin
        #200000;
        $display("FAIL[WPR=%0d]: scenario timeout", WPR);
        errors = errors + 1;
        done = 1;
    end
endmodule

// -------------------------------------------------------------------------
// Top: run both widths, aggregate, print one PASS/FAIL line.
// -------------------------------------------------------------------------
module tb_streaming_buffer;
    wire [31:0] err_a, err_b;
    wire        done_a, done_b;

    sb_scenario #(.WPR(7), .DEPTH_LOG2(2)) board_a (.errors(err_a), .done(done_a));
    sb_scenario #(.WPR(6), .DEPTH_LOG2(2)) board_b (.errors(err_b), .done(done_b));

    initial begin
        $dumpfile("tb_sb.vcd");
        $dumpvars(0, tb_streaming_buffer);

        wait (done_a && done_b);
        #1;
        if (err_a == 0)
            $display("ok:   Board A record (WORDS_PER_RECORD=7) — all checks passed");
        if (err_b == 0)
            $display("ok:   Board B record (WORDS_PER_RECORD=6) — all checks passed");

        if ((err_a + err_b) == 0)
            $display("\nPASS: streaming_buffer FIFO/drop + parameterized width (7 & 6)");
        else
            $display("\nFAIL: %0d test(s) failed (A=%0d, B=%0d)", err_a + err_b, err_a, err_b);
        $finish;
    end

    initial begin
        #300000;
        $display("FAIL: testbench timeout");
        $finish;
    end
endmodule
