`timescale 1ns/1ps
`default_nettype none
module core_load_tb;
reg clk=0;
always #5 clk=~clk;
reg rst_n=0;
reg [31:0] instr;
wire [31:0] pc, address, wd;
wire iv,dv,dw;
wire [3:0] strb;
reg ready=0;
integer writes=0;
reg [31:0] expected;
rv32e_core dut(.clk(clk),.rst_n(rst_n),
.imem_rdata(instr),.imem_ready(iv && pc==0),.imem_addr(pc),.imem_valid(iv),
.dmem_valid(dv),.dmem_write(dw),.dmem_wstrb(strb),.dmem_addr(address),
.dmem_wdata(wd),.dmem_ready(ready),.dmem_rdata(32'h80017f80));
always @(posedge clk) if(rst_n && dut.rf_we) begin
 if(dut.wb_rd_q !== 1 || dut.wb_data_q !== expected)
  $fatal(1,"Wrong load result: got %h expected %h",dut.wb_data_q,expected);
 writes=writes+1;
end
task check_load;
 input [2:0] f;
 input [1:0] offset;
 input [31:0] result;
 begin
 @(negedge clk); rst_n=0; ready=0; writes=0; expected=result;
 instr={10'b0,offset,5'd0,f,5'd1,7'b0000011};
 repeat(2) @(negedge clk);
 rst_n=1;
 while(!dv) @(negedge clk);
 if(dw !== 0 || strb !== 0 || address !== {30'b0,offset})
  $fatal(1,"Wrong load request");
 repeat(3) begin
  @(posedge clk); #1;
  if(writes!=0 || dv !== 1 || address !== {30'b0,offset})
   $fatal(1,"Load failed to wait");
 end
 @(negedge clk); ready=1;
 @(negedge clk); ready=0;
 repeat(3) @(negedge clk);
 if(writes!=1 || pc !== 4 || dut.REGFILE.allmahregisters[1] !== result)
  $fatal(1,"Load did not complete correctly");
 $display("PASS: load funct3=%d offset=%d value=%h",f,offset,result);
 end
endtask
initial begin
check_load(3'd0,2'd0,32'hffffff80);
check_load(3'd0,2'd1,32'h0000007f);
check_load(3'd0,2'd2,32'h00000001);
check_load(3'd0,2'd3,32'hffffff80);
check_load(3'd4,2'd0,32'h00000080);
check_load(3'd4,2'd1,32'h0000007f);
check_load(3'd4,2'd2,32'h00000001);
check_load(3'd4,2'd3,32'h00000080);
check_load(3'd1,2'd0,32'h00007f80);
check_load(3'd1,2'd2,32'hffff8001);
check_load(3'd5,2'd0,32'h00007f80);
check_load(3'd5,2'd2,32'h00008001);
check_load(3'd2,2'd0,32'h80017f80);
$finish;
end
initial begin #10000; $fatal(1,"Timeout"); end
endmodule
