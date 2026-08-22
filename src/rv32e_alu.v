module rv32e_alu(

    input wire [31:0] a,
    input wire [31:0] b,
    input wire [3:0] alu_op, // my opcode definitions: opcode[3]

    output reg [31:0] y,
    output wire eq,
    output wire lt,
    output wire ltu

); // no clk, purely combinational


assign eq = (a == b) ? 1 : 0; // eq = 1 if they're equal, 0 if they're not

assign lt = ($signed(a) < $signed(b)) ? 1 : 0; // bruh the ternary is unnecessary, eq = (a==b); works -_-

assign ltu = (a < b) ? 1 : 0;

// signed wire [31:0] s_a; should be wire signed [31:0] s_a, but dont need that since using $singned(a)!

always@(*) begin

    case (alu_op) // no begin for case statement!

        4'b0000: y = a + b;
        4'b0001: y = a - b;
        4'b0010: y = a & b;
        4'b0011: y = a | b;
        4'b0100: y = a ^ b;
        4'b0101: y = a << b[4:0];
        4'b0110: y = a >> b[4:0];
        4'b0111: y = $signed(a) >> b[4:0];
        4'b1000: y = $signed(a) < $signed(b);
        4'b1001: y = a < b;

        default: y = 32'b0; // inclusion of default case prevents inferred latch

    endcase

end

endmodule