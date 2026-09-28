`timescale 1ns/1ps
`default_nettype none

module core_program_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [31:0] imem_rdata;
    wire [31:0] imem_addr;
    wire imem_valid;
    // Stop supplying instructions after the four-instruction program.
    wire imem_ready = imem_valid && (imem_addr < 32'd16);
    wire dmem_valid, dmem_write;
    wire [3:0] dmem_wstrb;
    wire [31:0] dmem_addr, dmem_wdata;
    reg dmem_ready = 0;
    reg [31:0] memory_word = 32'hdeadbeef;
    integer stores = 0, loads = 0, writes = 0;

    always @(*) begin
        case (imem_addr)
            32'd0:  imem_rdata = 32'h00700093; // addi x1,x0,7
            32'd4:  imem_rdata = 32'h00508113; // addi x2,x1,5
            32'd8:  imem_rdata = 32'h00202023; // sw x2,0(x0)
            32'd12: imem_rdata = 32'h00002183; // lw x3,0(x0)
            default: imem_rdata = 32'h00000013;
        endcase
    end

    rv32e_core dut (
        .clk(clk), .rst_n(rst_n),
        .imem_rdata(imem_rdata), .imem_ready(imem_ready),
        .imem_addr(imem_addr), .imem_valid(imem_valid),
        .dmem_valid(dmem_valid), .dmem_write(dmem_write),
        .dmem_wstrb(dmem_wstrb), .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata), .dmem_ready(dmem_ready),
        .dmem_rdata(memory_word)
    );

    always @(posedge clk) begin
        if (rst_n && dut.rf_we) begin
            case (writes)
                0: if (dut.wb_rd_q !== 1 || dut.wb_data_q !== 7)
                    $fatal(1, "Expected x1=7");
                1: if (dut.wb_rd_q !== 2 || dut.wb_data_q !== 12)
                    $fatal(1, "Expected dependent ADDI x2=12");
                2: if (dut.wb_rd_q !== 3 || dut.wb_data_q !== 12)
                    $fatal(1, "Expected load x3=12");
                default: $fatal(1, "Unexpected extra register write");
            endcase
            writes = writes + 1;
        end
        if (rst_n && dmem_valid && dmem_ready) begin
            if (dmem_addr !== 0) $fatal(1, "Incorrect memory address");
            if (dmem_write) begin
                if (dmem_wstrb !== 4'b1111 || dmem_wdata !== 12)
                    $fatal(1, "Incorrect word-store payload");
                memory_word <= dmem_wdata;
                stores = stores + 1;
            end else begin
                loads = loads + 1;
            end
        end
    end

    // This core's interface completes the access on valid && ready;
    // read data must be valid at that edge. It has no separate response channel.
    task service_access;
        input expected_write;
        reg [68:0] saved_request;
        integer saved_writes;
        begin
            @(negedge clk);
            while (!dmem_valid) @(negedge clk);
            if (dmem_write !== expected_write)
                $fatal(1, "Unexpected memory operation order");
            saved_request = {dmem_write, dmem_wstrb, dmem_addr, dmem_wdata};
            saved_writes = writes;
            repeat (3) begin
                @(posedge clk); #1;
                if (dmem_valid !== 1 ||
                    {dmem_write, dmem_wstrb, dmem_addr, dmem_wdata} !== saved_request)
                    $fatal(1, "Memory request changed while waiting");
                if (writes != saved_writes)
                    $fatal(1, "Premature register write while memory stalled");
            end
            @(negedge clk); dmem_ready = 1;
            @(posedge clk); #1;
            if (dmem_valid !== 0)
                $fatal(1, "Request remained active after completion");
            @(negedge clk); dmem_ready = 0;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        @(negedge clk); rst_n = 1;
        service_access(1'b1);
        service_access(1'b0);
        wait (imem_valid && imem_addr == 16);
        repeat (3) begin @(posedge clk); #1; end
        if (stores != 1 || loads != 1 || writes != 3)
            $fatal(1, "Incorrect operation counts");
        if (memory_word !== 12 || dut.REGFILE.allmahregisters[1] !== 7 ||
            dut.REGFILE.allmahregisters[2] !== 12 ||
            dut.REGFILE.allmahregisters[3] !== 12)
            $fatal(1, "Incorrect final architectural state");
        $display("PASS: dependent arithmetic, SW/LW, delayed memory, no duplicate accesses");
        $finish;
    end

    initial begin
        #3000;
        $fatal(1, "Timeout");
    end
endmodule
