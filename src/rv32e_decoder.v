module rv32e_decoder(

    input wire [31:0] instr,

    // regfile addresses
    output wire [3:0] rs1_addr, 
    output wire [3:0] rs2_addr,
    output wire [3:0] rd_addr,

    // control signals
    output reg [3:0] alu_op, 
    output reg [2:0] imm_sel,
    // 000 I, S, B, U, 100 J
    output reg use_pc_as_alu_a,
    output reg use_imm_as_alu_b,
    output reg reg_write,
    output reg [1:0] wb_sel, // writeback select, val written back into rd
    // 00 ALU, 01 MEMORY, 10 PC_PLUS_4, 11 IMM
    output reg [2:0] branch_type,
    // 000 NONE, EQ, NE, LT, GE, LTU, GEU 110
    output reg jump,

    output reg mem_read,
    output reg mem_write,
    output reg [1:0] mem_size, 
    // 00 byte, 01 half, 10 word
    output reg load_unsigned,

    output reg illegal

);

reg instruction_match;

wire [6:0] opcode;
wire [2:0] funct3;
wire [6:0] funct7;

assign opcode = instr[6:0];
assign funct3 = instr[14:12];
assign funct7 = instr[31:25];

// missing a bit bc we only use regs 0 - 15
assign rs1_addr = instr[18:15];
assign rs2_addr = instr[23:20];
assign rd_addr = instr[10:7];
// needa check these bits for mistaken access tho

always@(*) // washed: an always block evals top to bottom when inputs change!
begin

instruction_match = 1'b0;
alu_op = 4'b0000;
imm_sel = 3'b000;
use_pc_as_alu_a = 1'b0;
use_imm_as_alu_b = 1'b0;
reg_write = 1'b0;
wb_sel = 2'b00;
branch_type = 3'b000;
jump = 1'b0;
mem_read = 1'b0;
mem_write = 1'b0;
mem_size = 2'b00;
load_unsigned = 1'b0;
illegal = 1'b1;

    case (opcode)

        7'b0110011: // op, reg to reg
        begin
            
            use_pc_as_alu_a = 1'b0;
            use_imm_as_alu_b = 1'b0;
            wb_sel = 2'b00;

            case ({funct7, funct3}) 

                10'b0000000_000: begin 
                    instruction_match = 1; alu_op = 4'b0000; // add
                end
                10'b0000000_001: begin 
                    instruction_match = 1; alu_op = 4'b0101; // sll
                end
                10'b0000000_010: begin 
                    instruction_match = 1; alu_op = 4'b1000; // slt
                end
                10'b0000000_011: begin 
                    instruction_match = 1; alu_op = 4'b1001; // sltu
                end
                10'b0000000_100: begin 
                    instruction_match = 1; alu_op = 4'b0100; // xor
                end
                10'b0000000_101: begin 
                    instruction_match = 1; alu_op = 4'b0110; // srl
                end
                10'b0000000_110: begin 
                    instruction_match = 1; alu_op = 4'b0011; // or
                end
                10'b0000000_111: begin 
                    instruction_match = 1; alu_op = 4'b0010; // and
                end

                10'b0100000_000: begin 
                    instruction_match = 1; alu_op = 4'b0001; // sub
                end
                10'b0100000_101: begin 
                    instruction_match = 1; alu_op = 4'b0111; // sra
                end

                default: begin instruction_match = 0; end

            endcase
            // checks not just valid instruction, but also that we're not accessing regs 16-31
            if (instruction_match && !instr[11] && !instr[19] && !instr[24]) 
            begin
                illegal = 0; reg_write = 1;
            end
    
        end

        7'b0010011: // op-imm, I imm
        begin 

            use_pc_as_alu_a = 1'b0;  // no use rs1
            use_imm_as_alu_b = 1'b1; // yes imm
            wb_sel = 2'b00; // ALU
            imm_sel = 3'b000; // I

            case (funct3) 

                3'b000: begin
                    instruction_match = 1; alu_op = 4'b0000; // addi
                end
                3'b001: begin
                    if (funct7 == 7'b0) begin
                        instruction_match = 1; alu_op = 4'b0101; // slli
                    end
                end
                3'b010: begin
                    instruction_match = 1; alu_op = 4'b1000; // slti
                end
                3'b011: begin
                    instruction_match = 1; alu_op = 4'b1001; // sltiu
                end
                3'b100: begin
                    instruction_match = 1; alu_op = 4'b0100; // xori
                end
                3'b101: begin
                    if (funct7 == 7'b0000000) begin
                        instruction_match = 1; alu_op = 4'b0110; // srli
                    end else if (funct7 == 7'b0100000) begin
                        instruction_match = 1; alu_op = 4'b0111; // srai
                    end
                end
                3'b110: begin
                    instruction_match = 1; alu_op = 4'b0011; // ori
                end
                3'b111: begin
                    instruction_match = 1; alu_op = 4'b0010; // andi
                end

                default: begin instruction_match = 0; end

            endcase
            // checks not just valid instruction, but also that we're not accessing regs 16-31
            if (instruction_match && !instr[11] && !instr[19]) 
            begin
                illegal = 0; reg_write = 1;
            end

        end

        7'b0000011: // loads, I imm
        begin

            alu_op = 4'b0000; // add
            imm_sel = 3'b000; // I
            wb_sel = 2'b01; // memory
            use_pc_as_alu_a = 0; // no using rs1
            use_imm_as_alu_b = 1; // yes using imm

            case (funct3) 
                // load unsigned unnecessary cuz default but whatever
                3'b000: begin instruction_match = 1; mem_size = 2'b00; load_unsigned = 0; end // lb
                3'b001: begin instruction_match = 1; mem_size = 2'b01; load_unsigned = 0; end // lh
                3'b010: begin instruction_match = 1; mem_size = 2'b10; load_unsigned = 0; end // lw
                3'b100: begin instruction_match = 1; mem_size = 2'b00; load_unsigned = 1; end // lbu
                3'b101: begin instruction_match = 1; mem_size = 2'b01; load_unsigned = 1; end // lhu
 
                default: instruction_match = 0;

            endcase

            if (instruction_match && !instr[11] && !instr[19]) // checks rs1 and rd
            begin
                illegal = 0; reg_write = 1; mem_read = 1;
            end

        end

        7'b0100011: // stores, S imm
        begin
            
            alu_op = 4'b0000; // add
            imm_sel = 3'b001; // S
            wb_sel = 2'b01; // memory
            use_pc_as_alu_a = 0; // no using rs1
            use_imm_as_alu_b = 1; // yes using imm

            case (funct3)

                3'b000: begin instruction_match = 1; mem_size = 2'b00; end // sb
                3'b001: begin instruction_match = 1; mem_size = 2'b01; end // sh
                3'b010: begin instruction_match = 1; mem_size = 2'b10; end // sw

                default: instruction_match = 0;

            endcase
            // STORES uses 2 source regs, rd bits are part of the imm in S type                                                            
            if (instruction_match && !instr[19] && !instr[24]) // sw x5, 12(x3) -> mem[x3 + 12] = x5 rs1 = x3 is base (where to), rs2 = x5 is data (what), imm = 12 offset
            begin                                              // lw x5, 12(x3) -> x5 = mem[x3 + 12] ahhhhhhhhhhhhh opposite! helps u select where in mem to write to!
                illegal = 0; mem_write = 1; // performing a mem_write, not a reg_write
            end // cuz theres no rd, the destination is memory! 

        end

        7'b1100011: // branches, B imm
        begin
            
            imm_sel = 3'b010; // B
            use_pc_as_alu_a = 1; // yes using pc
            use_imm_as_alu_b = 1; // yes using imm

            case (funct3)

                3'b000: begin instruction_match = 1; branch_type = 3'b001; end // beq
                3'b001: begin instruction_match = 1; branch_type = 3'b010; end // bne
                3'b100: begin instruction_match = 1; branch_type = 3'b011; end // blt
                3'b101: begin instruction_match = 1; branch_type = 3'b100; end // bge
                3'b110: begin instruction_match = 1; branch_type = 3'b101; end // bltu
                3'b111: begin instruction_match = 1; branch_type = 3'b110; end // bgeu

                default: begin illegal = 1; branch_type = 3'b000; end // aka nothing cuz these are both defaults anyways

            endcase

            if (instruction_match && !instr[24] && !instr[19]) // checks that rs1 and rs2 are valid
            begin  
                illegal = 0;
            end else branch_type = 3'b000;

        end

        7'b0110111: // LUI
        begin
            
            if (!instr[11]) begin // makes sure rd reg is valid

                imm_sel = 3'b011; // U
                illegal = 0;
                reg_write = 1;
                wb_sel = 2'b11; // IMM

            end

        end

        7'b0010111: // AUIPC
        begin
            
            if (!instr[11]) begin // makes sure rd reg is valid

                imm_sel = 3'b011; // U
                illegal = 0;
                use_pc_as_alu_a = 1; // yes use pc
                use_imm_as_alu_b = 1; // yes use imm
                reg_write = 1; // necessary?
                alu_op = 4'b0000; // add
                wb_sel = 2'b00; // ALU

            end

        end

        7'b1101111: // JAL
        begin
            
            if (!instr[11]) begin // makes sure rd reg is valid

                imm_sel = 3'b100; // J
                illegal = 0;
                use_pc_as_alu_a = 1; // yes use pc
                use_imm_as_alu_b = 1; // yes use imm
                reg_write = 1; // necessary?
                alu_op = 4'b0000; // add
                wb_sel = 2'b10; // PC_PLUS_4
                jump = 1;

            end

        end

        7'b1100111: // JALR
        begin
            // for some reason also requires that funct3 == 3'b000
            if (!instr[11] && !instr[19] && funct3 == 3'b000) begin // makes sure rd & rs1 reg is valid

                imm_sel = 3'b000; // I
                illegal = 0;
                use_pc_as_alu_a = 0; // no use rs1
                use_imm_as_alu_b = 1; // yes use imm
                reg_write = 1; // necessary?
                alu_op = 4'b0000; // add
                wb_sel = 2'b10; // PC_PLUS_4
                jump = 1;

            end

        end

        default: ; // bruh

    endcase

end

endmodule
