`timescale 1ns/1ps
module tb_gpu_cpu;
    reg clk=0; always #5 clk=~clk;
    reg reset_n=0,run=0,restart=0,host_we=0,gfx_ready=0;
    reg [9:0] host_addr=0;
    reg [31:0] host_data=0;
    wire gfx_valid,busy,done,error;
    wire [7:0] gfx_port;
    wire [31:0] gfx_data,ir;
    wire [9:0] pc;
    wire [3:0] flags;
    gpu_cpu #(.PROGRAM_FILE(""),.IMEM_WORDS(64)) dut(.*);
    integer accepted=0;
    always @(posedge clk) if(reset_n && gfx_valid && gfx_ready) accepted<=accepted+1;
    task tick; begin @(posedge clk); #1; end endtask
    task put(input integer addr,input [31:0] data);
        begin @(negedge clk);host_we=1;host_addr=addr;host_data=data;tick();@(negedge clk);host_we=0;end
    endtask
    task start;
        begin @(negedge clk);restart=1;run=1;tick();@(negedge clk);restart=0;end
    endtask
    task stop;
        begin @(negedge clk);run=0;restart=1;gfx_ready=0;tick();@(negedge clk);restart=0;end
    endtask
    task output_word(input [7:0] port,input [31:0] data,input integer pause);
        integer n; reg found;
        begin
            found=0;
            for(n=0;n<100;n=n+1) begin tick();if(gfx_valid)begin found=1;break;end end
            if(!found || gfx_port!==port || gfx_data!==data)
                $fatal(1,"OUT got port%h data%h expected %h %h pc%0d",gfx_port,gfx_data,port,data,pc);
            if(pause) begin @(negedge clk);run=0;end
            repeat(5) begin tick();if(!gfx_valid || gfx_data!==data || gfx_port!==port)$fatal(1,"backpressure changed command");end
            @(negedge clk);gfx_ready=1;tick();@(negedge clk);gfx_ready=0;
            if(pause)begin repeat(3)tick();if(gfx_valid)$fatal(1,"duplicate after pause");@(negedge clk);run=1;end
        end
    endtask
    task await_halt(input integer fault);
        integer n;
        begin
            for(n=0;n<100;n=n+1) begin tick();if(done||error)break;end
            if(fault ? (!error||done||busy) : (!done||error||busy))
                $fatal(1,"halt mismatch fault%0d done%b err%b busy%b pc%0d",fault,done,error,busy,pc);
        end
    endtask
    initial begin
        repeat(3)tick();@(negedge clk);reset_n=1;
        put(0,32'h11000064);put(1,32'h12000014);put(2,32'h23120000);put(3,32'hA0300001);
        put(4,32'hE40089AC);put(5,32'h1500CDEF);put(6,32'h24450000);put(7,32'hA0400002);
        put(8,32'h1600FFFF);put(9,32'hD7610000);put(10,32'hA0700003);
        put(11,32'h98600000);put(12,32'hA0800004);put(13,32'h49100000);put(14,32'hA0900005);
        put(15,32'h1A000001);put(16,32'h1B000004);put(17,32'h7CAB0000);put(18,32'hA0C00006);
        put(19,32'h8CCA0000);put(20,32'hA0C00007);put(21,32'h69110000);
        put(22,32'hC0900019);put(23,32'hF0000001);put(24,32'hB0000017);
        put(25,32'h32220000);put(26,32'hA0000009);put(27,32'hF0000000);
        start();
        output_word(1,120,1);output_word(2,32'h89ABCDEF,0);output_word(3,1,0);
        output_word(4,32'hFFFFFFFF,0);output_word(5,0,0);output_word(6,16,0);
        output_word(7,8,0);output_word(9,0,0);await_halt(0);
        if(flags!==4'b0101 || accepted!=8)$fatal(1,"flags/count wrong");
        repeat(10)tick();if(gfx_valid||busy)$fatal(1,"HALT restarted by RUN");
        stop();put(0,32'hF0000001);start();await_halt(1);
        stop();put(0,32'hB0000064);start();await_halt(1);
        stop();put(0,32'hB000003F);put(63,0);start();await_halt(1);
        // R0 is immutable; replacement program plus restart clears prior error.
        stop();put(0,32'h10000055);put(1,32'hA000000A);put(2,32'hF0000000);
        start();output_word(10,0,0);await_halt(0);
        // Restart explicitly cancels a command that has never been accepted.
        stop();put(0,32'hA000000B);start();wait(gfx_valid);stop();
        repeat(5)tick();if(gfx_valid||error||done)$fatal(1,"restart did not clear pending OUT");
        $display("PASS tb_gpu_cpu: ISA, LUI, branches, RAM replacement, faults, pause, backpressure");$finish;
    end
    initial begin #100000;$fatal(1,"CPU test timeout");end
endmodule
