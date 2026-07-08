`timescale 1ns / 1ps

// Smoke test for streaming_buffer.v:
//   1. Three write_pulses with distinct payloads.
//   2. Verify the BRAM model holds the expected 4 words per record at the
//      expected byte offsets.
//   3. Verify write_ptr advances by 1 per pulse and wraps within DEPTH.
//   4. Verify sample_count is monotonic.
//   5. Verify the multi-board sync flag is set on the record written
//      immediately after a sync_reset, and clears on subsequent records.
//      Includes the coincident sync_reset + write_pulse case (the steady-
//      state when boards are already aligned).
//
// Encoding note: bram_data for freq_raw is {sync_flag, freq_raw[30:0]}.
// The host PC masks the high bit out when reading the count. The expected
// BRAM word for an input freq_raw = X with flag F is therefore
// {F, X[30:0]}.
module tb_streaming_buffer;

    localparam DEPTH_LOG2 = 4;          // 16 records (small for fast sim)
    localparam DEPTH      = 1 << DEPTH_LOG2;
    localparam BYTE_BITS  = DEPTH_LOG2 + 4;

    reg               clk          = 0;
    reg               rst_n        = 0;
    reg               enable       = 0;
    reg               write_pulse  = 0;
    reg               sync_reset   = 0;
    reg  [31:0]       freq_raw_in  = 32'd0;
    reg  [31:0]       freq_dec_in  = 32'd0;
    reg  [15:0]       amp_raw_in   = 16'd0;
    reg  [15:0]       amp_dec_in   = 16'd0;

    wire [3:0]              bram_we;
    wire [BYTE_BITS-1:0]    bram_addr;
    wire [31:0]             bram_data;
    wire [DEPTH_LOG2-1:0]   write_ptr;
    wire [31:0]             sample_count;

    streaming_buffer #(.DEPTH_LOG2(DEPTH_LOG2)) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .enable       (enable),
        .write_pulse  (write_pulse),
        .sync_reset   (sync_reset),
        .freq_raw_in  (freq_raw_in),
        .freq_dec_in  (freq_dec_in),
        .amp_raw_in   (amp_raw_in),
        .amp_dec_in   (amp_dec_in),
        .bram_we      (bram_we),
        .bram_addr    (bram_addr),
        .bram_data    (bram_data),
        .write_ptr    (write_ptr),
        .sample_count (sample_count)
    );

    always #4 clk = ~clk;

    // Behavioral BRAM model
    reg [31:0] bram [0:DEPTH*4 - 1];
    always @(posedge clk) begin
        if (bram_we[0]) bram[bram_addr >> 2] <= bram_data;
    end

    integer errors = 0;

    task issue_pulse(input [31:0] fr, input [31:0] fd, input [15:0] ar, input [15:0] ad);
        begin
            @(negedge clk);
            freq_raw_in = fr;
            freq_dec_in = fd;
            amp_raw_in  = ar;
            amp_dec_in  = ad;
            write_pulse = 1'b1;
            @(negedge clk);
            write_pulse = 1'b0;
            repeat (5) @(posedge clk);   // let the 4-cycle write FSM run + 1 settle
            #1;
        end
    endtask

    // Pulse sync_reset for exactly 1 cycle, then idle (no write).
    task pulse_sync_only;
        begin
            @(negedge clk); sync_reset = 1'b1;
            @(negedge clk); sync_reset = 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    // Pulse sync_reset and write_pulse on the same cycle (steady-state aligned boards).
    task issue_pulse_with_sync(input [31:0] fr, input [31:0] fd, input [15:0] ar, input [15:0] ad);
        begin
            @(negedge clk);
            freq_raw_in = fr;
            freq_dec_in = fd;
            amp_raw_in  = ar;
            amp_dec_in  = ad;
            write_pulse = 1'b1;
            sync_reset  = 1'b1;
            @(negedge clk);
            write_pulse = 1'b0;
            sync_reset  = 1'b0;
            repeat (5) @(posedge clk);
            #1;
        end
    endtask

    task check_record(input [DEPTH_LOG2-1:0] slot,
                      input               expect_flag,
                      input [31:0] fr, input [31:0] fd,
                      input [15:0] ar, input [15:0] ad);
        reg [31:0] expected_word0;
        begin
            expected_word0 = {expect_flag, fr[30:0]};
            if (bram[slot*4 + 0] !== expected_word0) begin
                $display("FAIL: slot %0d freq_raw word = %h, expected %h (flag=%0b, count=%h)",
                         slot, bram[slot*4 + 0], expected_word0, expect_flag, fr[30:0]);
                errors = errors + 1;
            end
            if (bram[slot*4 + 1] !== fd) begin
                $display("FAIL: slot %0d freq_dec = %h, expected %h", slot, bram[slot*4 + 1], fd);
                errors = errors + 1;
            end
            if (bram[slot*4 + 2] !== {16'd0, ar}) begin
                $display("FAIL: slot %0d amp_raw = %h, expected %h", slot, bram[slot*4 + 2], ar);
                errors = errors + 1;
            end
            if (bram[slot*4 + 3] !== {16'd0, ad}) begin
                $display("FAIL: slot %0d amp_dec = %h, expected %h", slot, bram[slot*4 + 3], ad);
                errors = errors + 1;
            end
        end
    endtask

    integer i;
    integer n;

    initial begin
        $dumpfile("tb_sb.vcd");
        $dumpvars(0, tb_streaming_buffer);

        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        enable = 1;

        // --- Existing payload smoke tests (sync_reset stays low → flag=0) ---
        issue_pulse(32'hAABBCCDD, 32'h11223344, 16'h5566, 16'h7788);
        check_record(0, 1'b0, 32'hAABBCCDD, 32'h11223344, 16'h5566, 16'h7788);
        if (write_ptr !== 4'd1) begin
            $display("FAIL: write_ptr after first record = %0d, expected 1", write_ptr);
            errors = errors + 1;
        end
        if (sample_count !== 32'd1) begin
            $display("FAIL: sample_count = %0d, expected 1", sample_count);
            errors = errors + 1;
        end else $display("ok:   first record stored, flag=0");

        issue_pulse(32'h12345678, 32'h9ABCDEF0, 16'h1111, 16'h2222);
        check_record(1, 1'b0, 32'h12345678, 32'h9ABCDEF0, 16'h1111, 16'h2222);

        // --- Disable should suppress writes ---
        enable = 0;
        issue_pulse(32'hDEADBEEF, 32'hCAFEF00D, 16'h0001, 16'h0002);
        if (write_ptr !== 4'd2) begin
            $display("FAIL: write_ptr advanced while disabled (now %0d, expected 2)", write_ptr);
            errors = errors + 1;
        end else
            $display("ok:   disable suppresses write_pulse");
        enable = 1;

        // --- §2.3 sync flag: pre-sync record has flag=1, next record flag=0 ---
        pulse_sync_only;       // sync_reset arrives between writes
        issue_pulse(32'h00010002, 32'h00030004, 16'h0005, 16'h0006);
        // Slot 2 should now have the flagged record.
        check_record(2, 1'b1, 32'h00010002, 32'h00030004, 16'h0005, 16'h0006);
        $display("ok:   record after sync_reset has flag=1");

        // Next record (no fresh sync) should be flag=0.
        issue_pulse(32'h00010003, 32'h00030005, 16'h0007, 16'h0008);
        check_record(3, 1'b0, 32'h00010003, 32'h00030005, 16'h0007, 16'h0008);
        $display("ok:   subsequent record (no fresh sync) has flag=0");

        // --- Coincident sync_reset + write_pulse (steady-state aligned boards) ---
        issue_pulse_with_sync(32'h00010004, 32'h00030006, 16'h0009, 16'h000A);
        check_record(4, 1'b1, 32'h00010004, 32'h00030006, 16'h0009, 16'h000A);
        $display("ok:   coincident sync_reset + write_pulse → record flagged");

        // The very next record should once again have flag=0.
        issue_pulse(32'h00010005, 32'h00030007, 16'h000B, 16'h000C);
        check_record(5, 1'b0, 32'h00010005, 32'h00030007, 16'h000B, 16'h000C);
        $display("ok:   record after the synced one has flag=0");

        // --- Fill remaining slots to verify wrap still works ---
        // We're at write_ptr=6, sample_count=6. Fill until wrap.
        for (i = 6; i < DEPTH + 6; i = i + 1) begin
            issue_pulse(32'h0000_0000 | i, 32'h1000_0000 | i, i[15:0], i[15:0]);
        end

        if (sample_count !== DEPTH + 6) begin
            $display("FAIL: sample_count=%0d, expected %0d", sample_count, DEPTH + 6);
            errors = errors + 1;
        end else
            $display("ok:   sample_count monotonic across wrap");

        if (write_ptr !== 4'd6) begin
            $display("FAIL: write_ptr did not wrap to 6 (got %0d)", write_ptr);
            errors = errors + 1;
        end else
            $display("ok:   write_ptr wrapped to 6 after DEPTH+6 writes");

        if (errors == 0) $display("\nPASS: streaming_buffer smoke tests");
        else             $display("\nFAIL: %0d test(s) failed", errors);
        $finish;
    end

    initial begin
        #100000;
        $display("FAIL: testbench timeout");
        $finish;
    end

endmodule
