`timescale 1ns / 1ps
//
// tb_regfile.v — self-checking testbench for the GENERATED core_regs AXI4-Lite slave.
//
// Verifies: const reads (magic, buffer_depth), rw reset values, rw write/read-back
// across the address range, byte-strobed partial writes, and ro/input read-back.
//
// Run (from repo root):
//   iverilog -g2012 -o build/tb_regfile.out regspec/tb/tb_regfile.v regspec/generated/core_regs.v
//   vvp build/tb_regfile.out
//
module tb_regfile;

    localparam ADDR_WIDTH = 7;
    localparam DATA_WIDTH = 32;

    reg                    clk = 0;
    reg                    rstn = 0;
    reg  [ADDR_WIDTH-1:0]  awaddr;
    reg                    awvalid;
    wire                   awready;
    reg  [DATA_WIDTH-1:0]  wdata;
    reg  [3:0]             wstrb;
    reg                    wvalid;
    wire                   wready;
    wire [1:0]             bresp;
    wire                   bvalid;
    reg                    bready;
    reg  [ADDR_WIDTH-1:0]  araddr;
    reg                    arvalid;
    wire                   arready;
    wire [DATA_WIDTH-1:0]  rdata;
    wire [1:0]             rresp;
    wire                   rvalid;
    reg                    rready;

    // ro/input ports we drive to known values
    reg  [31:0] in_bufwptr = 0, in_bufcnt = 0;
    reg  [31:0] in_meas_ch0 = 0;

    core_regs #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) dut (
        .control_o(), .scratch_o(), .gate_cycles_o(), .threshold_o(), .buffer_enable_o(),
        .buffer_write_ptr_i(in_bufwptr), .buffer_sample_count_i(in_bufcnt),
        .nco_tuning_word_ch0_o(), .nco_amplitude_ch0_o(), .pid_setpoint_ch0_o(), .pid_gains_ch0_o(),
        .pid_output_ch0_i(32'h0), .lock_status_ch0_i(32'h0),
        .meas_count_ch0_i(in_meas_ch0), .meas_amp_ch0_i(32'h0),
        .nco_tuning_word_ch1_o(), .nco_amplitude_ch1_o(), .pid_setpoint_ch1_o(), .pid_gains_ch1_o(),
        .pid_output_ch1_i(32'h0), .lock_status_ch1_i(32'h0),
        .meas_count_ch1_i(32'h0), .meas_amp_ch1_i(32'h0),
        .S_AXI_ACLK(clk), .S_AXI_ARESETN(rstn),
        .S_AXI_AWADDR(awaddr), .S_AXI_AWVALID(awvalid), .S_AXI_AWREADY(awready),
        .S_AXI_WDATA(wdata), .S_AXI_WSTRB(wstrb), .S_AXI_WVALID(wvalid), .S_AXI_WREADY(wready),
        .S_AXI_BRESP(bresp), .S_AXI_BVALID(bvalid), .S_AXI_BREADY(bready),
        .S_AXI_ARADDR(araddr), .S_AXI_ARVALID(arvalid), .S_AXI_ARREADY(arready),
        .S_AXI_RDATA(rdata), .S_AXI_RRESP(rresp), .S_AXI_RVALID(rvalid), .S_AXI_RREADY(rready)
    );

    always #4 clk = ~clk;   // 125 MHz

    integer errors = 0;

    task axi_write(input [ADDR_WIDTH-1:0] a, input [31:0] d, input [3:0] strb);
        begin
            @(posedge clk);
            awaddr <= a; awvalid <= 1'b1;
            wdata  <= d; wstrb <= strb; wvalid <= 1'b1;
            // wait until both address & data accepted
            @(posedge clk);
            while (!(awready && wready)) @(posedge clk);
            awvalid <= 1'b0; wvalid <= 1'b0;
            bready <= 1'b1;
            @(posedge clk);
            while (!bvalid) @(posedge clk);
            @(posedge clk);
            bready <= 1'b0;
        end
    endtask

    task axi_read(input [ADDR_WIDTH-1:0] a, output [31:0] d);
        begin
            @(posedge clk);
            araddr <= a; arvalid <= 1'b1; rready <= 1'b1;
            @(posedge clk);
            while (!arready) @(posedge clk);
            arvalid <= 1'b0;
            while (!rvalid) @(posedge clk);
            d = rdata;
            @(posedge clk);
            rready <= 1'b0;
        end
    endtask

    task check(input [255:0] name, input [31:0] got, input [31:0] exp);
        begin
            if (got !== exp) begin
                $display("FAIL %0s: got 0x%08x, expected 0x%08x", name, got, exp);
                errors = errors + 1;
            end else begin
                $display("ok   %0s = 0x%08x", name, got);
            end
        end
    endtask

    reg [31:0] v;

    initial begin
        awvalid=0; wvalid=0; bready=0; arvalid=0; rready=0; awaddr=0; wdata=0; wstrb=0; araddr=0;
        repeat (4) @(posedge clk);
        rstn <= 1'b1;
        repeat (2) @(posedge clk);

        // --- reset values ---
        axi_read(7'h00, v); check("control reset",       v, 32'h0000_0001);
        axi_read(7'h28, v); check("nco_amp_ch0 reset",   v, 32'h0000_3fff);
        axi_read(7'h0c, v); check("gate_cycles reset",   v, 32'h0013_12d0);

        // --- const registers ---
        axi_read(7'h04, v); check("magic const",         v, 32'hdead_beef);
        axi_read(7'h20, v); check("buffer_depth const",  v, 32'h0000_0400);

        // --- rw write/read across the map ---
        axi_write(7'h08, 32'h1234_5678, 4'hf);
        axi_read (7'h08, v); check("scratch roundtrip",  v, 32'h1234_5678);
        axi_write(7'h44, 32'hcafe_babe, 4'hf);   // nco_tuning_word_ch1
        axi_read (7'h44, v); check("nco_tw_ch1 rw",      v, 32'hcafe_babe);

        // --- byte-strobed partial write ---
        axi_write(7'h08, 32'h0000_0000, 4'hf);
        axi_write(7'h08, 32'hffff_ffff, 4'b0011);  // low 2 bytes only
        axi_read (7'h08, v); check("wstrb partial",      v, 32'h0000_ffff);

        // --- ro/input read-back ---
        in_meas_ch0 = 32'h0bad_f00d;
        @(posedge clk);
        axi_read(7'h3c, v); check("meas_count_ch0 input", v, 32'h0bad_f00d);
        in_bufwptr = 32'h0000_0201;
        @(posedge clk);
        axi_read(7'h18, v); check("buffer_write_ptr input", v, 32'h0000_0201);

        // --- write to a read-only offset must NOT change the const read ---
        axi_write(7'h04, 32'h0, 4'hf);
        axi_read (7'h04, v); check("magic still const",  v, 32'hdead_beef);

        if (errors == 0)
            $display("PASS: tb_regfile — all checks passed");
        else
            $display("FAIL: tb_regfile — %0d error(s)", errors);
        $finish;
    end

    // safety timeout
    initial begin
        #100000;
        $display("FAIL: tb_regfile timeout");
        $finish;
    end

endmodule
