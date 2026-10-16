`timescale 1ns/1ps
module tb_gpu_system;
    reg clk=0;
    always #10 clk=~clk;
    reg reset_n=0, start=0, rd=0, wr=0;
    reg [5:0] addr=0;
    reg [31:0] wdata=0;
    wire [31:0] rdata;
    wire waitreq, vclk, hs, vs, blank, sync_n;
    wire [7:0] red,green,blue;
    gpu_system dut(.clk(clk),.reset_n(reset_n),.demo_start(start),
        .avs_address(addr),.avs_read(rd),.avs_write(wr),.avs_writedata(wdata),
        .avs_readdata(rdata),.avs_waitrequest(waitreq),
        .VGA_CLK(vclk),.VGA_HS(hs),.VGA_VS(vs),.VGA_BLANK_N(blank),
        .VGA_SYNC_N(sync_n),.VGA_R(red),.VGA_G(green),.VGA_B(blue));
    integer cycles, color_pixels;
    task read_reg(input [5:0] index, output [31:0] value);
        begin @(negedge clk); addr=index; rd=1; #1; value=rdata;
        @(negedge clk); rd=0; end
    endtask
    reg [31:0] value;
    initial begin
        repeat(6) @(negedge clk); reset_n=1;
        read_reg(0,value);
        if(value!==32'h47505533) $fatal(1,"Wrong host ID");
        @(negedge clk);start=1;@(negedge clk);start=0;
        cycles=0;
        while(dut.frame_count==0 && cycles<6000000) begin
            @(negedge clk);cycles=cycles+1;
        end
        if(dut.frame_count==0) $fatal(1,"No complete graphical frame from assembly program");
        read_reg(16,value);
        if(value!==0) $fatal(1,"Demo ended with errors: %h",value);
        color_pixels=0;
        repeat(900000) begin
            @(negedge clk);
            if(blank && {red,green,blue}!==24'b0) color_pixels=color_pixels+1;
            if(blank && (^({red,green,blue})===1'bx)) $fatal(1,"Undefined VGA pixel");
        end
        if(color_pixels<1000) $fatal(1,"Expected rendered image, got black frame");
        $display("PASS tb_gpu_system first_frame_cycles=%0d colored_samples=%0d",cycles,color_pixels);
        $finish;
    end
    initial begin #160000000; $fatal(1,"System test timed out"); end
endmodule
