/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_tinytapeout_chill (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs

    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)

    // ah, so these pins are bidirectional! chosen whether theyre input or output based on output enable pin

    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

// Instruction interface
    wire [31:0] imem_addr;
    wire        imem_valid;
    reg  [31:0] imem_rdata;

    // Data interface
    wire        dmem_valid;
    wire        dmem_write;
    wire [3:0]  dmem_wstrb;
    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    reg  [31:0] dmem_rdata;

    // One writable 32-bit word, mapped at byte address 4.
    reg [31:0] data_word;

    rv32e_core core (
        .clk         (clk),
        .rst_n       (rst_n),

        .imem_addr   (imem_addr),
        .imem_valid  (imem_valid),
        .imem_rdata  (imem_rdata),
        .imem_ready  (1'b1),

        .dmem_valid  (dmem_valid),
        .dmem_write  (dmem_write),
        .dmem_wstrb  (dmem_wstrb),
        .dmem_addr   (dmem_addr),
        .dmem_wdata  (dmem_wdata),
        .dmem_rdata  (dmem_rdata),
        .dmem_ready  (1'b1)
    );

    // Program ROM: combinational instruction lookup.
    always @(*) begin
        case (imem_addr)
            32'h00000000: imem_rdata = 32'h00002083; // lw x1,0(x0)
            32'h00000004: imem_rdata = 32'h00508113; // addi x2,x1,5
            32'h00000008: imem_rdata = 32'h00202223; // sw x2,4(x0)
            32'h0000000c: imem_rdata = 32'hff5ff06f; // jal x0,-12
            default:      imem_rdata = 32'h0000006f; // jump to self
        endcase
    end

    // Read the aligned word containing the requested byte address.
    always @(*) begin
        case (dmem_addr[31:2])
            30'd0:   dmem_rdata = {24'b0, ui_in};
            30'd1:   dmem_rdata = data_word;
            default: dmem_rdata = 32'b0;
        endcase
    end

    // Apply byte enables when a store completes.
    integer lane;
    always @(posedge clk) begin
        if (!rst_n) begin
            data_word <= 32'b0;
        end else if (dmem_valid && dmem_write &&
                     dmem_addr[31:2] == 30'd1) begin
            for (lane = 0; lane < 4; lane = lane + 1) begin
                if (dmem_wstrb[lane])
                    data_word[8*lane +: 8]
                        <= dmem_wdata[8*lane +: 8];
            end
        end
    end

    assign uo_out  = data_word[7:0];
    assign uio_out = 8'b0;
    assign uio_oe  = 8'b0;

    wire _unused = &{ena, uio_in, imem_valid, 1'b0};

endmodule