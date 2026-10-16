`timescale 1ns/1ps
// Uses the ACTUAL dual-port altsyncram adaptation and C-generated command list.
// Models RAM transactions after the HPS AXI/Avalon bridge, not ARM/Linux boot.
module tb_gpu_mailbox #(parameter REAL_RAM=0, QUICK=0);
 reg clk=0;always #10 clk=~clk;
 reg reset_n=0;
 wire [13:0] ma;wire mw;wire [31:0] md,mq,gd,gq;wire [5:0] ga;wire gr,gw,mbbusy,waitreq;
 reg [12:0] ha=0;reg [7:0] hbe=0;reg hw=0;reg [63:0] hd=0;wire [63:0] hq;
 wire vclk,hs,vs,blank,sync_n;wire [7:0] red,green,blue;
 gpu_mailbox #(.FIFO_TIMEOUT(1000)) mb(.clk(clk),.reset_n(reset_n),
  .mem_address(ma),.mem_write(mw),.mem_writedata(md),.mem_readdata(mq),
  .gpu_address(ga),.gpu_read(gr),.gpu_write(gw),.gpu_writedata(gd),.gpu_readdata(gq),.busy(mbbusy));
 generate if(REAL_RAM) begin: vendor_ram
 soc_system_onchip_memory2_0 #(.INIT_FILE("professor/soc_system/synthesis/submodules/soc_system_onchip_memory2_0.hex")) ram(
  .clk(clk),.address(ha),.byteenable(hbe),.chipselect(1'b1),.clken(1'b1),
  .freeze(1'b0),.reset(!reset_n),.reset_req(!reset_n),.write(hw),.writedata(hd),.readdata(hq),
  .gpu_address(ma),.gpu_write(mw),.gpu_writedata(md),.gpu_readdata(mq));
 end else begin: fast_ram
  // Same one-cycle, 64-bit byte-enabled HPS / 32-bit FPGA port contract.
  // Vendor primitive is tested separately by tb_gpu_mailbox_ram.
  reg [31:0] memory[0:16383];reg [31:0] read_b;reg [63:0] read_a;
  integer k;
  initial for(k=0;k<16384;k=k+1)memory[k]=0;
  assign mq=read_b;assign hq=read_a;
  always @(posedge clk) begin
   read_b<=memory[ma];read_a<={memory[{ha,1'b1}],memory[{ha,1'b0}]};
   if(mw)memory[ma]<=md;
   if(hw)begin
    for(k=0;k<4;k=k+1)begin
     if(hbe[k])memory[{ha,1'b0}][k*8+:8]<=hd[k*8+:8];
     if(hbe[k+4])memory[{ha,1'b1}][k*8+:8]<=hd[32+k*8+:8];
    end
   end
  end
 end endgenerate
 gpu_system dut(.clk(clk),.reset_n(reset_n),.demo_start(1'b0),
  .avs_address(ga),.avs_read(gr),.avs_write(gw),.avs_writedata(gd),.avs_readdata(gq),.avs_waitrequest(waitreq),
  .VGA_CLK(vclk),.VGA_HS(hs),.VGA_VS(vs),.VGA_BLANK_N(blank),.VGA_SYNC_N(sync_n),.VGA_R(red),.VGA_G(green),.VGA_B(blue));
 task put(input integer address,input [31:0] value);
  @(negedge clk);ha=address/8;hbe=(address&4)?8'hf0:8'h0f;hd={value,value};hw=1;
  @(negedge clk);hw=0;
 endtask
 task get(input integer address,output [31:0] value);
  @(negedge clk);ha=address/8;hw=0;
  @(negedge clk);value=(address&4)?hq[63:32]:hq[31:0];
 endtask
 reg [31:0] seq=0,r,e,got;
 integer polls;
 task call(input [31:0] op,count,a,b,expected_error);
  put('h48,op);put('h4c,count);put('h50,a);put('h54,b);
  seq=seq+1;put('h40,seq);polls=0;r=0;
  while(r!==seq && polls<100000)begin get(8,r);polls=polls+1;end
  if(r!==seq)$fatal(1,"Mailbox timeout op=%d seq=%d state=%d",op,seq,mb.state);
  get('h14,e);if(e!==expected_error)$fatal(1,"Mailbox error %d expected %d op=%d",e,expected_error,op);
 endtask
 task reg_write(input [31:0] address,value);call(2,0,address,value,0);endtask
 task reg_read(input [31:0] address,output [31:0] value);call(1,0,address,0,0);get('h18,value);endtask
 function [7:0] pixel(input integer x,y);
  pixel=dut.graphics.front_bank ? dut.graphics.framebuffer1[y*320+x][7:0] : dut.graphics.framebuffer0[y*320+x][7:0];
 endfunction
 reg [31:0] scene[0:8192];
 integer i,j,count,fd,pixels;
 reg [31:0] old_out,old_frame;
 initial begin
  $readmemh("tests/demo_commands.hex",scene);
  repeat(6)@(negedge clk);reset_n=1;repeat(100)@(negedge clk);
  get(0,r);if(r!==32'h48505347)$fatal(1,"No mailbox MAGIC %h",r);
  get(4,r);if(r!==1)$fatal(1,"64/32 lane mapping ABI failed");
  reg_read(0,got);if(got!==32'h47505533)$fatal(1,"GPU ID mismatch");
  // Invalid descriptors must not write IMEM or send commands.
  call(99,0,0,0,1);call(1,0,3,0,2);call(3,1025,0,0,2);call(4,1,0,0,3);
  // External program traverses shared RAM -> mailbox -> IMEM -> PC/IR -> OUT.
  put('h100,32'h1100002a);put('h104,32'ha0100000);put('h108,32'hf0000000);
  call(3,3,0,0,0);get('h1c,r);if(r!==3)$fatal(1,"Wrong program length");
  reg_write(4,3);repeat(100)@(negedge clk);
  reg_read(8,got);if(!got[1]||got[2])$fatal(1,"External program did not halt cleanly");
  if(dut.graphics.scroll_x!==42)$fatal(1,"External OUT did not reach graphics");
  if(QUICK)begin $display("PASS tb_gpu_mailbox_ram actual altsyncram dual-port/32-bit lanes/ABI/ISA verified");$finish;end
  reg_write(4,2);reg_write(4,5);
  count=scene[0];if(count<2000||count>4096)$fatal(1,"Bad C scene size");
  for(i=0;i<count*2;i++)put('h100+i*4,scene[i+1]);
  call(4,count,0,0,0);get('h1c,r);if(r!==count)$fatal(1,"Partial scene transfer");
  wait(dut.frame_count==1);@(negedge clk);
  if(dut.graphics_error)$fatal(1,"Graphics error after HPS scene");
  if(pixel(64,16)!==4 || pixel(224,60)!==10 || pixel(210,100)!==8 || pixel(142,152)!==13)
   $fatal(1,"Tile / triangle / rectangle / sprite mismatch: %d %d %d %d",pixel(64,16),pixel(224,60),pixel(210,100),pixel(142,152));
  // Duplicate sequence must not redraw/replay the list.
  old_out=dut.host.out_count;put('h40,seq);repeat(100)@(negedge clk);
  if(dut.host.out_count!==old_out)$fatal(1,"Duplicate sequence executed twice");
  @(negedge vs);@(posedge vs);fd=$fopen("simulation/hps_demo.ppm","wb");
  if(!fd)$fatal(1,"Cannot create capture");$fwrite(fd,"P6\n640 480\n255\n");pixels=0;
  while(vs)begin @(posedge vclk);#1;if(blank)begin
   if($isunknown({red,green,blue}))$fatal(1,"Unknown VGA pixel");
   $fwrite(fd,"%c%c%c",red,green,blue);pixels=pixels+1;end end
  $fclose(fd);if(pixels!=307200)$fatal(1,"Bad VGA timing/capture %d",pixels);
  // Change a tile and sprite using a SECOND externally published block.
  put('h100,'h20);put('h104,5*40+5);put('h108,'h21);put('h10c,1);
  put('h110,'h10);put('h114,0);put('h118,'h11);put('h11c,160);
  put('h120,'hf0);put('h124,0);call(4,5,0,0,0);
  wait(dut.frame_count==2);@(negedge clk);
  if(pixel(40,40)!==4||pixel(166,152)!==13)$fatal(1,"External tile/sprite update failed");
  // Invalid port halfway through a batch: explicit partial count, no stale port.
  put('h100,0);put('h104,7);put('h108,256);put('h10c,0);call(4,2,0,0,4);
  get('h1c,r);if(r!==1)$fatal(1,"Wrong partial count");
  // Full FIFO/backpressure: fill 64, reject the 65th after bounded wait.
  repeat(20)@(negedge clk);force dut.command_ready=1'b0;
  for(i=0;i<65;i++)begin put('h100+i*8,0);put('h104+i*8,i);end
  call(4,65,0,0,5);get('h1c,r);if(r!==64)$fatal(1,"FIFO timeout lost count %d",r);
  release dut.command_ready;repeat(300)@(negedge clk);
  if(dut.host.fifo_count!==0||dut.graphics.scroll_x!==63)$fatal(1,"FIFO did not drain in order: count=%d scroll=%d",dut.host.fifo_count,dut.graphics.scroll_x);
  // Reset clears protocol/queue, does not replay a stale committed request.
  @(negedge clk);reset_n=0;repeat(6)@(negedge clk);reset_n=1;
  repeat(150)@(negedge clk);get(8,r);if(r!==0)$fatal(1,"Reset retained DONE");
  get('h40,r);if(r!==0||dut.host.out_count!==0)$fatal(1,"Stale request replayed");
  $display("PASS tb_gpu_mailbox commands=%0d VGA_pixels=%0d RAM_lanes/ISA/FIFO/errors/reset verified",count,pixels);$finish;
 end
 initial begin #160000000;$fatal(1,"Global mailbox simulation timeout");end
endmodule
