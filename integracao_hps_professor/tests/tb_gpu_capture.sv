`timescale 1ns/1ps
// Capture the real VGA stream produced by the assembled demonstration program.
// The output PPM is an HDL simulation artifact, not a software reconstruction.
module tb_gpu_capture;
    reg clk=0;
    always #10 clk=~clk;
    reg reset_n=0,start=0;
    wire [31:0] rdata;
    wire waitreq,vclk,hs,vs,blank,sync_n;
    wire [7:0] red,green,blue;
    gpu_system dut(
        .clk(clk),.reset_n(reset_n),.demo_start(start),
        .avs_address(6'd0),.avs_read(1'b0),.avs_write(1'b0),.avs_writedata(32'd0),
        .avs_readdata(rdata),.avs_waitrequest(waitreq),
        .VGA_CLK(vclk),.VGA_HS(hs),.VGA_VS(vs),.VGA_BLANK_N(blank),
        .VGA_SYNC_N(sync_n),.VGA_R(red),.VGA_G(green),.VGA_B(blue)
    );
    integer image_file,pixels,nonblack;
    initial begin
        repeat(6) @(negedge clk);
        reset_n=1;
        @(negedge clk);start=1;
        @(negedge clk);start=0;
        wait(dut.frame_count!=0);
        if(dut.graphics_error) $fatal(1,"Assembly demo reported a graphics error");
        // Begin in the vertical back porch so the following active sample is
        // exactly the top-left pixel. Stop at the next vertical sync pulse.
        @(negedge vs);@(posedge vs);
        image_file=$fopen("simulation/demo.ppm","wb");
        if(!image_file) $fatal(1,"Cannot open simulation/demo.ppm; create simulation directory first");
        $fwrite(image_file,"P6\n640 480\n255\n");
        pixels=0;nonblack=0;
        while(vs) begin
            @(posedge vclk);#1;
            if(blank) begin
                if($isunknown({red,green,blue})) $fatal(1,"Unknown pixel in captured VGA frame");
                $fwrite(image_file,"%c%c%c",red,green,blue);
                pixels=pixels+1;
                if({red,green,blue}!=0) nonblack=nonblack+1;
            end
        end
        $fclose(image_file);
        if(pixels!=640*480) $fatal(1,"Incomplete VGA capture: %0d pixels",pixels);
        if(nonblack<10000) $fatal(1,"Unexpected mostly black assembly demonstration");
        if(dut.graphics_error) $fatal(1,"Graphics error while capturing frame");
        $display("PASS tb_gpu_capture pixels=%0d nonblack=%0d file=simulation/demo.ppm",pixels,nonblack);
        $finish;
    end
    initial begin #100000000;$fatal(1,"VGA capture timeout");end
endmodule
