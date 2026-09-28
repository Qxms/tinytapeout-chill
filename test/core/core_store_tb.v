`timescale 1ns/1ps
`default_nettype none
module core_store_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [31:0] instruction, store_instruction;
    wire [31:0] pc, address, data;
    wire iv, dv, dw;
    wire [3:0] strobes;
    reg ready = 0;
    reg [31:0] memory_word;
    integer accepted = 0;
    integer lane;
    rv32e_core dut (
        .clk(clk), .rst_n(rst_n), .imem_rdata(instruction),
        .imem_ready(iv && pc < 12), .imem_addr(pc), .imem_valid(iv),
        .dmem_valid(dv), .dmem_write(dw), .dmem_wstrb(strobes),
        .dmem_addr(address), .dmem_wdata(data), .dmem_ready(ready),
        .dmem_rdata(memory_word)
    );
    always @(*) begin
        case (pc)
            0: instruction = 32'h123450b7; // lui x1,0x12345
            4: instruction = 32'h6ab08093; // addi x1,x1,0x6ab
            8: instruction = store_instruction;
            default: instruction = 32'h00000013;
        endcase
    end
    // Memory returns/updates the aligned word containing the byte address.
    always @(posedge clk) begin
        if (rst_n && dv && ready) begin
            if (dw !== 1 || address[31:2] !== 0)
                $fatal(1, "Unexpected memory operation");
            for (lane = 0; lane < 4; lane = lane + 1)
                if (strobes[lane])
                    memory_word[8*lane +: 8] <= data[8*lane +: 8];
            accepted = accepted + 1;
        end
    end
    task check_store;
        input [2:0] funct3;
        input [1:0] offset;
        input [3:0] expected_strobes;
        input [31:0] expected_word;
        reg [68:0] held;
        begin
            @(negedge clk);
            rst_n = 0; ready = 0; accepted = 0;
            memory_word = 32'h11223344;
            store_instruction = {7'b0, 5'd1, 5'd0, funct3,
                                 3'b0, offset, 7'b0100011};
            repeat (2) @(negedge clk);
            rst_n = 1;
            while (!dv) @(negedge clk);
            if (address !== {30'b0, offset} || strobes !== expected_strobes)
                $fatal(1, "Wrong address/strobes at offset %d", offset);
            held = {dw, strobes, address, data};
            repeat (3) begin
                @(posedge clk); #1;
                if (dv !== 1 || {dw, strobes, address, data} !== held)
                    $fatal(1, "Store changed during stall");
            end
            @(negedge clk); ready = 1;
            @(posedge clk); #1;
            if (memory_word !== expected_word)
                $fatal(1, "Got %h expected %h", memory_word, expected_word);
            @(negedge clk); ready = 0;
            repeat (2) @(negedge clk);
            if (accepted != 1 || pc !== 12 || iv !== 1)
                $fatal(1, "Store did not finish exactly once");
            $display("PASS: size=%d offset=%d strobes=%b memory=%h",
                     funct3, offset, expected_strobes, memory_word);
        end
    endtask
    initial begin
        check_store(0, 0, 4'b0001, 32'h112233ab);
        check_store(0, 1, 4'b0010, 32'h1122ab44);
        check_store(0, 2, 4'b0100, 32'h11ab3344);
        check_store(0, 3, 4'b1000, 32'hab223344);
        check_store(1, 0, 4'b0011, 32'h112256ab);
        check_store(1, 2, 4'b1100, 32'h56ab3344);
        check_store(2, 0, 4'b1111, 32'h123456ab);
        $display("PASS: aligned stores, preserved neighbors, delayed memory");
        $finish;
    end
    initial begin
        #10000;
        $fatal(1, "Timeout");
    end
endmodule
