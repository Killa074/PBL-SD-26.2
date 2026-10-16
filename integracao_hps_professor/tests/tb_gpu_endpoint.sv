`timescale 1ns/1ps
module tb_gpu_endpoint;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,bus_read=0,bus_write=0;
    reg [5:0] bus_address=0;
    reg [3:0] bus_byteenable=15;
    wire bus_waitrequest,bus_readdatavalid,core_read,core_write;
    wire [31:0] bus_readdata;
    wire [5:0] core_address;
    wire [31:0] core_readdata={26'h123456,core_address};
    gpu_avmm_endpoint dut(.*);
    initial begin
        #1;if(!bus_waitrequest||core_read||core_write)$fatal(1,"reset isolation");
        repeat(4)@(negedge clk);reset_n=1;
        bus_read=1;bus_address=3;
        @(posedge clk);#1;
        if(!bus_readdatavalid||bus_readdata!={26'h123456,6'd3})$fatal(1,"read latency/data");
        @(negedge clk);bus_address=5;
        @(posedge clk);#1;
        if(!bus_readdatavalid||bus_readdata!={26'h123456,6'd5})$fatal(1,"back-to-back read");
        @(negedge clk);bus_read=0;bus_write=1;bus_address=7;
        #1;if(!core_write||core_address!=7)$fatal(1,"full word write");
        bus_byteenable=3;
        #1;if(!core_write||core_address!=63)$fatal(1,"partial write must become host invalid access");
        @(posedge clk);#1;if(bus_readdatavalid)$fatal(1,"extra read response");
        @(negedge clk);reset_n=0;
        #1;if(core_write||!bus_waitrequest||bus_readdatavalid)$fatal(1,"reset pending response");
        $display("PASS tb_gpu_endpoint: one-cycle reads, back-to-back, partial-write rejection, reset isolation");
        $finish;
    end
endmodule
