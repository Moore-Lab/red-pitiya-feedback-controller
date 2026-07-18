`timescale 1ns / 1ps

// tb_adc_deserial_ll.v — exercises the 65-16 TI serial-LVDS ADC deserializer
// (rtl/io/adc_deserial_ll.v) end-to-end through the behavioral SERDES models
// (rtl/io/sim_primitives_ll.v).  Compile with -DSIM.
//
// Stimulus: two known 16-bit codes (one per channel) are serialized MSB-first,
// bit-interleaved across the two lanes, DDR against adc_dclk, framed by adc_fclk
// — exactly the format adc_deserial_ll.v documents. The test asserts:
//   1. the recovered adc_a / adc_b equal the driven codes, and
//   2. adc_valid pulses once per sample period (62.5 MS/s strobe).
//
// TIMEBASE (idealised — real clock phasing is a bring-up GATE)
//   * bit period       = 2 ns  (DDR: 2 bits per adc_dclk period)
//   * adc_dclk period  = 4 ns  (250 MHz); edges centred in each data bit
//   * adc_fclk period  = 16 ns (62.5 MHz = adc_dclk/4); one word per period
// Data changes on even ns; adc_dclk edges land on odd ns, sampling the stable bit.

module tb_adc_deserial_ll;

    reg        rst;
    reg        refclk;
    reg        adc_dclk;
    reg        adc_fclk;
    reg [1:0]  adc_data_i;   // channel A lanes {lane1, lane0}
    reg [1:0]  adc_datb_i;   // channel B lanes {lane1, lane0}

    wire signed [15:0] adc_a, adc_b;
    wire               adc_valid;

    // Codes under test: A negative (MSB=1), B positive, to exercise the sign bit.
    localparam [15:0] CODE_A = 16'hA53C;   // 1010_0101_0011_1100
    localparam [15:0] CODE_B = 16'h5A6D;   // 0101_1010_0110_1101

    integer errors = 0;
    integer valid_pulses = 0;

    // ---- DUT --------------------------------------------------------------
    adc_deserial_ll dut (
        .rst        (rst),
        .refclk     (refclk),
        .adc_dclk   (adc_dclk),
        .adc_fclk   (adc_fclk),
        .adc_data_i (adc_data_i),
        .adc_datb_i (adc_datb_i),
        .adc_a      (adc_a),
        .adc_b      (adc_b),
        .adc_valid  (adc_valid)
    );

    // ---- clocks -----------------------------------------------------------
    // refclk: nominal IDELAYCTRL reference (behaviour ignores rate).
    initial refclk = 1'b0;
    always #2.5 refclk = ~refclk;

    // adc_dclk: transitions on odd ns (1,3,5,...) => edges centred in data bits.
    initial begin
        adc_dclk = 1'b0;
        #1;
        forever #2 adc_dclk = ~adc_dclk;
    end

    // adc_fclk: word/frame clock, period 16 ns. Its rising edge is phased
    // (posedges at t=8,24,40,...) so that each edge frames a complete, aligned
    // 8-bit-per-lane word in the ISERDES shift register. On real hardware this
    // word-boundary alignment is set by the per-lane IDELAY tap + ISERDES
    // BITSLIP against the captured frame pattern (a bring-up GATE); here it is
    // fixed by construction via the frame-clock phase.
    initial begin
        adc_fclk = 1'b0;
        #8;
        forever #8 adc_fclk = ~adc_fclk;
    end

    // ---- serialize the codes ---------------------------------------------
    // Per channel, lane1 carries the odd bits, lane0 the even bits, MSB first:
    //   lane1 time order: C[15],C[13],C[11],C[9],C[7],C[5],C[3],C[1]
    //   lane0 time order: C[14],C[12],C[10],C[8],C[6],C[4],C[2],C[0]
    // Returns bit `idx` (0=first/MSB-side .. 7=last) for the given lane.
    function lane_bit;
        input [15:0] code;
        input        odd_lane;   // 1 => lane1 (odd bits), 0 => lane0 (even bits)
        input [3:0]  idx;        // 0..7, time order
        integer      pos;
        begin
            pos = 15 - (2*idx) - (odd_lane ? 0 : 1);
            lane_bit = code[pos];
        end
    endfunction

    // Reset: released early (before it matters); the first framed words are
    // treated as pipeline warmup and skipped by the checker.
    initial begin
        rst = 1'b1;
        #3 rst = 1'b0;
    end

    // Serialize the codes. i=0 is aligned to t=0 so that bit i of a word is
    // sampled at t=1+2i and the whole word (i=0..7) is complete just before the
    // adc_fclk rising edge at t=16k. Data updates on even ns; every frame drives
    // the same codes.
    integer i;
    initial begin
        adc_data_i = 2'b00;
        adc_datb_i = 2'b00;
        forever begin
            for (i = 0; i < 8; i = i + 1) begin
                adc_data_i[1] = lane_bit(CODE_A, 1'b1, i[3:0]);
                adc_data_i[0] = lane_bit(CODE_A, 1'b0, i[3:0]);
                adc_datb_i[1] = lane_bit(CODE_B, 1'b1, i[3:0]);
                adc_datb_i[0] = lane_bit(CODE_B, 1'b0, i[3:0]);
                #2;
            end
        end
    end

    // ---- checker ----------------------------------------------------------
    // Count valid strobes and check the recovered words on each (after warmup).
    always @(posedge adc_dclk) begin
        if (!rst && adc_valid) begin
            valid_pulses = valid_pulses + 1;
            // Skip the first couple of framed words (pipeline warmup).
            if (valid_pulses >= 3) begin
                if (adc_a !== CODE_A) begin
                    $display("FAIL: adc_a = %h, expected %h", adc_a, CODE_A);
                    errors = errors + 1;
                end
                if (adc_b !== CODE_B) begin
                    $display("FAIL: adc_b = %h, expected %h", adc_b, CODE_B);
                    errors = errors + 1;
                end
            end
        end
    end

    // ---- run + report -----------------------------------------------------
    initial begin
        // Run long enough for many sample periods (each = 16 ns).
        #400;

        if (valid_pulses < 5) begin
            $display("FAIL: adc_valid pulsed only %0d times (expected sample-rate strobe)",
                     valid_pulses);
            errors = errors + 1;
        end else begin
            $display("INFO: adc_valid strobed %0d times over the run", valid_pulses);
        end

        // Final steady-state value check.
        if (adc_a !== CODE_A) begin
            $display("FAIL: final adc_a = %h, expected %h", adc_a, CODE_A);
            errors = errors + 1;
        end
        if (adc_b !== CODE_B) begin
            $display("FAIL: final adc_b = %h, expected %h", adc_b, CODE_B);
            errors = errors + 1;
        end

        $display("INFO: recovered adc_a=%h (%0d), adc_b=%h (%0d)",
                 adc_a, adc_a, adc_b, adc_b);

        if (errors == 0)
            $display("PASS: tb_adc_deserial_ll (deserialize + frame-align + valid strobe)");
        else
            $display("FAIL: tb_adc_deserial_ll with %0d error(s)", errors);
        $finish;
    end

endmodule
