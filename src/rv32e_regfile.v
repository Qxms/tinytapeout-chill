module rv32e_regfile (

    input wire clk,

    input wire [3:0] rs1_addr,
    input wire [3:0] rs2_addr,

    input wire [3:0] rd_addr,
    input wire [31:0] rd_data,
    input wire rd_we,
    
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data
);

    reg [31:0] allmahregisters [0:15]; // 32 bits, array of 16

    // WIRES assigned with assign, REGS assigned with always@(*)
    assign rs1_data = (rs1_addr == 4'b0) ? 32'b0 : allmahregisters[rs1_addr];
    assign rs2_data = (rs2_addr == 4'b0) ? 32'b0 : allmahregisters[rs2_addr];

    // if the addr is 0, then assign 0, otherwise, assign whatever's in regfile

    // niche, but more hw friendly than the allmahregisters[0] <= 0 approach

    always@(posedge clk) begin

        if (rd_we && rd_addr != 4'b0) 
        begin
            allmahregisters[rd_addr] <= rd_data;
        end

    end 

endmodule
