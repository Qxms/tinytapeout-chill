`timescale 1ns/1ps
`default_nettype none

module core_smoke_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg imem_ready = 0;
    wire [31:0] imem_addr;
    wire imem_valid;
    wire dmem_valid;
    wire dmem_write;
    wire [3:0] dmem_wstrb;
    wire [31:0] dmem_addr, dmem_wdata;

    rv32e_core dut (
        .clk(clk), .rst_n(rst_n),
        // addi x1, x0, 7: expected architectural result x1=7, PC=4.
        .imem_rdata(32'h00700093), .imem_ready(imem_ready),
        .imem_addr(imem_addr), .imem_valid(imem_valid),
        .dmem_valid(dmem_valid), .dmem_write(dmem_write),
        .dmem_wstrb(dmem_wstrb), .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata), .dmem_ready(1'b0),
        .dmem_rdata(32'b0)
    );

    integer writes = 0;
    always @(posedge clk) begin
        if (rst_n && dut.rf_we) begin
            if (dut.wb_rd_q !== 4'd1 || dut.wb_data_q !== 32'd7)
                $fatal(1, "Incorrect register write destination/data");
            writes = writes + 1;
        end
    end

    // Observe after nonblocking register updates have settled.
    task tick;
        begin @(posedge clk); #1; end
    endtask

    initial begin
        tick;
        tick;
        @(negedge clk); rst_n = 1;
        // Withhold the instruction for two cycles: no architectural work yet.
        repeat (2) begin
            tick;
            if (imem_valid !== 1 || imem_addr !== 0 || writes != 0)
                $fatal(1, "Fetch did not wait correctly");
        end
        @(negedge clk); imem_ready = 1;
        tick;
        if (dut.state !== 2'd1 || dut.ir !== 32'h00700093)
            $fatal(1, "Instruction was not captured into EXECUTE");
        @(negedge clk); imem_ready = 0;
        tick;
        if (dut.state !== 2'd3 || writes != 0 || dmem_valid !== 0)
            $fatal(1, "ADDI did not reach WRITEBACK without memory access");
        tick;
        if (dut.REGFILE.allmahregisters[1] !== 32'd7 || writes != 1)
            $fatal(1, "ADDI did not write x1=7 exactly once");
        if (imem_addr !== 32'd4 || imem_valid !== 1)
            $fatal(1, "ADDI did not return to FETCH at PC=4");
        repeat (2) tick;
        if (writes != 1) $fatal(1, "Register write repeated while fetch stalled");
        $display("PASS: fetch wait, ADDI x1=7, one writeback, PC=4");
        $finish;
    end

    initial begin
        #1000;
        $fatal(1, "Timeout");
    end
endmodule
