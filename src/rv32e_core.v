`default_nettype none

module rv32e_core(

    input wire clk,
    input wire rst_n,

    // instruction memory
    input wire [31:0] imem_rdata,
    input wire imem_ready,
    output wire [31:0] imem_addr,
    output wire imem_valid,

    // data memory
    output wire dmem_valid,
    output wire dmem_write,
    output wire [3:0] dmem_wstrb,
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,

    input wire dmem_ready,
    input wire [31:0] dmem_rdata

);

localparam FETCH = 2'd0;
localparam EXECUTE = 2'd1;
localparam MEMORY = 2'd2;
localparam WRITEBACK = 2'd3;

reg [1:0] state;
reg [31:0] pc; // program counter (addr of current instruction)
reg [31:0] ir; // instruction reg, WHAT the instruction itself is

wire [3:0] alu_op;
wire [2:0] imm_sel;
wire [31:0] imm;
wire use_pc_as_alu_a;
wire use_imm_as_alu_b;
wire [3:0] rs1_addr;
wire [3:0] rs2_addr;
wire [3:0] rd_addr;
wire [31:0] rs1_data;
wire [31:0] rs2_data;
wire [31:0] rd_data;

wire reg_write;
wire [1:0] wb_sel;
wire [2:0] branch_type;
wire jump;

wire mem_read;
wire mem_write;
wire [1:0] mem_size; // must use to distinguish W/H/B

reg [1:0] mem_size_q;
reg load_unsigned_q;

wire load_unsigned;

wire illegal;

wire [31:0] alu_a;
wire [31:0] alu_b;
wire [31:0] alu_y; // out

reg [31:0]  wb_data_q; // readable?
reg [3:0]   wb_rd_q;
reg         wb_we_q;
reg [31:0]  next_pc_q; // niche register #15

/////////////////////////////////////////////
//   TO SAVE STUFF FOR MEMORY, LIKE DATA   //
/////////////////////////////////////////////

reg [31:0]  mem_addr_q; // gotta store these in FF for a while
reg [31:0]  mem_wdata_q;
reg [3:0]   mem_wstrb_q; // lets us sync various comb pieces
reg         mem_write_q;

reg [3:0]  store_wstrb;
reg [31:0] store_wdata;

assign dmem_valid = (state == MEMORY); // when we're in memory
assign dmem_write = mem_write_q;
assign dmem_wstrb = mem_wstrb_q; // all synchronous, updates on edge
assign dmem_addr  = mem_addr_q;
assign dmem_wdata = mem_wdata_q;


// MUXES FOR ALU OPERANDS
assign alu_a = use_pc_as_alu_a ? pc : rs1_data;
assign alu_b = use_imm_as_alu_b ? imm : rs2_data;

assign imem_valid = (state == FETCH);
assign imem_addr = pc;

wire rf_we; // regfile write enable

assign rf_we = (rst_n && (state == WRITEBACK) && wb_we_q);
// only possible during the single clk cycle of WRITEBACK
// wb_we_q and state WRITEBACK are both synchronous to clk

wire is_jalr;
assign is_jalr = (ir[6:0] == 7'b1100111); // shouldnt i js move this into decoder?

///////////////////////////////////////////////////////
//  NEED THIS CUZ ALU COMPARES ALU & IMM FOR BRANCH  //
///////////////////////////////////////////////////////

wire branch_eq;
wire branch_lt; // the 3 ops that the alu will misproduce
wire branch_ltu;

assign branch_eq = (rs1_data == rs2_data);
assign branch_ltu = (rs1_data < rs2_data);
assign branch_lt = ($signed(rs1_data) < $signed(rs2_data)); // OBVIOUSLY the signed one uses $signed

reg branch_taken;

always@(*)
begin

    store_wdata = 32'b0;
    store_wstrb = 4'b0;

    case (mem_size) 
    
        2'b00: begin // byte
            store_wstrb = 4'b0001 << alu_y[1:0];
            store_wdata = rs2_data << {alu_y[1:0], 3'b000};
        end

        2'b01: begin // halfword
            store_wstrb = 4'b0011 << alu_y[1:0];
            store_wdata = rs2_data << {alu_y[1:0], 3'b000};
        end

        2'b10: begin // word
            store_wstrb = 4'b1111;
            store_wdata = rs2_data;
        end

        default: ;
    endcase
end

always@(*) // mini alu for branch comparisons
begin

    branch_taken = 0;

    case (branch_type) // 000 NONE, EQ, NE, LT, GE, LTU, GEU 110

        3'b001: branch_taken = branch_eq;
        3'b010: branch_taken = !branch_eq; // can very well equal 0 if cond isnt met,
        3'b011: branch_taken = branch_lt;  // but still a branch instr nonetheless
        3'b100: branch_taken = !branch_lt;
        3'b101: branch_taken = branch_ltu;
        3'b110: branch_taken = !branch_ltu;

        default: branch_taken = 0; // does this infer a latch? or does atl having it do what we need?

    endcase

end

always@(posedge clk) 
begin

    if (!rst_n) 
    begin
        
        pc <= 32'b0;
        ir <= 32'b0;
        state <= FETCH;

        // RESET ALL SYNC REGS TOO
        wb_data_q <= 32'b0;
        wb_rd_q <= 4'b0;
        wb_we_q <= 1'b0;
        next_pc_q <= 32'b0;

        mem_addr_q  <= 32'b0;
        mem_wdata_q <= 32'b0;
        mem_wstrb_q <= 4'b0;
        mem_write_q <= 1'b0;

        mem_size_q <= 2'b0;
        load_unsigned_q <= 1'b0;

    end
    else 
    begin

        case (state)

            FETCH: begin // capture an instruction

                if (imem_valid && imem_ready) begin

                    ir <= imem_rdata; // ahhh yes, when updates grabs instruction from imem
                    state <= EXECUTE;

                end

            end

            EXECUTE: begin // calculate and save results
                
                if (illegal) begin // js treat as a rst

                    pc <= 32'b0;
                    ir <= 32'b0;
                    state <= FETCH;

                    // RESET ALL SYNC REGS TOO
                    wb_data_q <= 32'b0;
                    wb_rd_q <= 4'b0;
                    wb_we_q <= 1'b0;
                    next_pc_q <= 32'b0;

                    mem_addr_q  <= 32'b0;
                    mem_wdata_q <= 32'b0;
                    mem_wstrb_q <= 4'b0;
                    mem_write_q <= 1'b0;

                    mem_size_q <= 2'b0;
                    load_unsigned_q <= 1'b0;

                end else if (mem_read || mem_write) begin // loads or stores

                    mem_addr_q <= alu_y; // same for both: rs1 + imm
                    mem_wdata_q <= store_wdata;
                    mem_write_q <= mem_write; // see if we write or nah, save or js load

                    mem_wstrb_q <= mem_write ? store_wstrb : 4'b0000; // updated!
                    // what are byte strobes? // each represents 8 bits
                    wb_rd_q <= rd_addr; // load destination
                    wb_we_q <= mem_read; // why do we need mem read to enable writeback? feels like the wrong thing to be checking

                    mem_size_q <= mem_size;
                    load_unsigned_q <= load_unsigned; // storing genuinely ALL of the decoder data

                    next_pc_q <= pc + 32'd4;
                    state <= MEMORY;

                end else if (branch_type != 3'b000) begin // branches

                    pc <= branch_taken ? alu_y : pc + 32'd4; // if correct, use branch, ow use pc + 4 normal
                    state <= FETCH;

                end else if (jump) begin // jump (JAL OR JALR)

                    wb_data_q <= pc + 32'd4; // THIS is the data we're saving
                    wb_rd_q <= rd_addr;
                    wb_we_q <= reg_write;
                    next_pc_q <= (!is_jalr) ? alu_y : alu_y & 32'b11111111_11111111_11111111_11111110; // if jalr, jump_target = that. if not, then = alu_y
                    state <= WRITEBACK;

                end else if (reg_write) begin // everything else, aka ordinary ALU & LUI & AUIPC

                    wb_rd_q <= rd_addr;
                    wb_we_q <= reg_write;     
                    next_pc_q <= pc + 32'd4;

                    case (wb_sel) // 00 ALU, 01 MEMORY, 10 PC_PLUS_4, 11 IMM

                        2'b00: wb_data_q <= alu_y;
                        // 2'b01: wb_data_q <= /* the plot twist, its NOT THERE?!*/ ; captured later apparently
                        // more accurately, mem shenanigans are dealt with in MEMORY and loads or stores section
                        2'b10: wb_data_q <= pc + 32'd4;
                        2'b11: wb_data_q <= imm;

                        default: wb_data_q <= 32'b0;

                    endcase
                    
                    state <= WRITEBACK;

                end else begin
                    // final resort, should never reach here
                end

            end

            MEMORY: begin // TODO: implement byte and halfword ops too
            
                if (dmem_ready && dmem_valid) begin // dmem_valid js indicates when state == MEMORY, doubles as output
                    
                    if (mem_write_q) begin // then we're storing!
                        // we alr updated everything! _q's are wired to module out's!
                        pc <= next_pc_q; // aka js pc + 4
                        state <= FETCH;

                    end else begin
                        // gets synchronously loaded into regfile!
                        wb_data_q <= dmem_rdata; // ahh this is loading
                        state <= WRITEBACK;

                    end // nothing else we needa do to prevent latching?

                end

            end

            WRITEBACK: begin // permanently update a register and PC

                pc <= next_pc_q; // next_pc figured out in EXECUTE
                state <= FETCH;
            
            end

        endcase

    end


end

rv32e_alu ALU (

    .a      (alu_a), // dont do the mux inside the input, bad vibes
    .b      (alu_b),
    .alu_op (alu_op),

    .y      (alu_y),
    .eq     (),
    .lt     (),
    .ltu    ()          // more readable spacing?

);

rv32e_decoder DECODER (

    .instr(ir), // only i, rest is o

    // regfile addresses
    .rs1_addr(rs1_addr), 
    .rs2_addr(rs2_addr),
    .rd_addr(rd_addr),

    // control signals
    .alu_op(alu_op), 
    .imm_sel(imm_sel),
    // 000 I, S, B, U, 100 J
    .use_pc_as_alu_a(use_pc_as_alu_a),
    .use_imm_as_alu_b(use_imm_as_alu_b),
    .reg_write(reg_write),
    .wb_sel(wb_sel), // writeback select, val written back into rd
    // 00 ALU, 01 MEMORY, 10 PC_PLUS_4, 11 IMM
    .branch_type(branch_type),
    // 000 NONE, EQ, NE, LT, GE, LTU, GEU 110
    .jump(jump),

    .mem_read(mem_read), // signals load
    .mem_write(mem_write),
    .mem_size(mem_size), 
    // 00 byte, 01 half, 10 word
    .load_unsigned(load_unsigned),

    .illegal(illegal)

);

rv32e_regfile REGFILE (

    .clk        (clk),

    .rs1_addr   (rs1_addr),
    .rs2_addr   (rs2_addr),

    .rd_addr    (wb_rd_q),
    .rd_data    (wb_data_q),
    .rd_we      (rf_we),

    .rs1_data   (rs1_data), // above i, here & below o
    .rs2_data   (rs2_data)

);

rv32e_immgen IMMGEN ( // ALL INPUTS ASSIGNED

    .instr(ir),
    .imm_sel(imm_sel),
    .imm(imm)

);

endmodule
