`timescale 1ns/1ps
module tb_gpu_host;
    reg clk=0;always #5 clk=~clk;
    reg reset_n=0,avs_read=0,avs_write=0,demo_start=0;
    reg [5:0] avs_address=0;
    reg [31:0] avs_writedata=0;
    wire [31:0] avs_readdata;
    wire avs_waitrequest,gfx_valid;
    wire [7:0] gfx_port;
    wire [31:0] gfx_data;
    reg gfx_ready=0,gfx_busy=0,gfx_done=0,gfx_error=0;
    reg [31:0] gfx_frame_count=0;
    gpu_host #(.PROGRAM_FILE(""),.IMEM_WORDS(64)) dut(.*);
    integer received=0,i,n;
    reg [39:0] log[0:255];
    reg [31:0] value;
    always @(posedge clk) if(reset_n && gfx_valid && gfx_ready) begin
        log[received]<={gfx_port,gfx_data};received<=received+1;
    end
    task tick;begin @(posedge clk);#1;end endtask
    task write_reg(input [7:0] address,input [31:0] data);
        begin @(negedge clk);avs_address=address>>2;avs_writedata=data;avs_write=1;
            tick();if(avs_waitrequest)$fatal(1,"unexpected bus stall");
            @(negedge clk);avs_write=0;end
    endtask
    task read_reg(input [7:0] address,output [31:0] data);
        begin @(negedge clk);avs_address=address>>2;avs_read=1;#1;data=avs_readdata;
            tick();@(negedge clk);avs_read=0;end
    endtask
    task expect_reg(input [7:0] address,input [31:0] expected);
        reg [31:0] actual;
        begin read_reg(address,actual);if(actual!==expected)$fatal(1,"reg%h got%h wanted%h",address,actual,expected);end
    endtask
    initial begin
        repeat(3)tick();@(negedge clk);reset_n=1;
        expect_reg(0,32'h47505533);expect_reg(4,0);expect_reg(8,32'h10);expect_reg(56,64);
        write_reg(4,4); // passive, paused
        for(i=0;i<64;i=i+1)begin write_reg(48,i);write_reg(52,i*17);end
        expect_reg(56,0);if(gfx_valid || received!=0)$fatal(1,"paused FIFO consumed");
        write_reg(52,32'hDEADBEEF);expect_reg(64,4); // reject overflow
        write_reg(4,0);expect_reg(4,4);expect_reg(64,12); // reject mode change with queued commands
        write_reg(64,12);expect_reg(64,0);
        write_reg(4,5);wait(gfx_valid);repeat(4)tick();
        if(gfx_port!==0 || gfx_data!==0)$fatal(1,"FIFO first pair changed");
        write_reg(4,4);repeat(4)begin tick();if(!gfx_valid)$fatal(1,"pause withdrew offered command");end
        @(negedge clk);gfx_ready=1;repeat(5)tick();
        if(received!=1)$fatal(1,"pause must drain exactly offered command");
        write_reg(4,5);
        for(n=0;n<300;n=n+1)begin tick();if(received==64)break;end
        if(received!=64)$fatal(1,"FIFO did not drain");
        for(i=0;i<64;i=i+1)if(log[i]!=={8'(i),32'(i*17)})$fatal(1,"FIFO order/data mismatch%0d",i);
        expect_reg(56,64);expect_reg(36,64);
        @(negedge clk);gfx_busy=1;gfx_ready=0;gfx_frame_count=9;
        write_reg(4,7);expect_reg(64,8);expect_reg(4,5);expect_reg(60,9);
        @(negedge clk);gfx_busy=0;write_reg(4,8);expect_reg(4,0);expect_reg(64,0);
        write_reg(52,42);expect_reg(64,64);write_reg(64,64);
        // Program RAM upload, automatic addressing, protected boundary and RUN.
        write_reg(12,0);write_reg(16,32'h1100002A);write_reg(16,32'hA0100003);write_reg(16,32'hF0000000);
        expect_reg(12,3);
        write_reg(12,64);write_reg(16,0);expect_reg(64,2);expect_reg(12,64);write_reg(64,2);
        write_reg(4,3);write_reg(16,0); // prohibited while running
        expect_reg(64,2);write_reg(64,2);
        wait(gfx_valid);write_reg(4,5);expect_reg(4,1);expect_reg(64,8);write_reg(64,8);
        @(negedge clk);gfx_ready=1;
        for(n=0;n<50;n=n+1)begin read_reg(8,value);if(value[1])break;end
        if(!value[1] || value[0] || value[2])$fatal(1,"active CPU completion bad%h",value);
        if(received!=65 || log[64]!==40'h030000002A)$fatal(1,"active output mismatch");
        expect_reg(28,42);expect_reg(32,3);expect_reg(36,1);
        // Reset clears queue/control/errors, preserves uploaded program RAM.
        @(negedge clk);reset_n=0;repeat(2)tick();@(negedge clk);reset_n=1;
        expect_reg(4,0);expect_reg(56,64);expect_reg(64,0);
        @(negedge clk);demo_start=1;tick();@(negedge clk);demo_start=0;
        for(n=0;n<50;n=n+1)begin tick();if(received==66)break;end
        if(received!=66 || log[65]!==40'h030000002A)$fatal(1,"KEY1/reloaded program failed");
        write_reg(8,0);expect_reg(64,1);write_reg(64,1);
        @(negedge clk);gfx_error=1;tick();read_reg(64,value);
        if(!value[5])$fatal(1,"missing gfx error");
        $display("PASS tb_gpu_host: FIFO order/full/pause, MMIO faults, modes, RAM upload, KEY1, status");$finish;
    end
    initial begin #100000;$fatal(1,"host test timeout");end
endmodule
