`timescale 1ns/1ps
module tb_gpu_graphics;
    reg clk=0; always #10 clk=~clk;
    reg reset_n=0,cmd_valid=0;
    reg [7:0] cmd_port=0;
    reg [31:0] cmd_data=0;
    wire cmd_ready,busy,frame_done,error;
    wire [31:0] frame_count;
    wire VGA_CLK,VGA_HS,VGA_VS,VGA_BLANK_N,VGA_SYNC_N;
    wire [7:0] VGA_R,VGA_G,VGA_B;
    gpu_graphics dut(.*);
    integer n;
    reg previous_bank=0;
    always @(negedge clk) if(reset_n) begin
        if(dut.front_bank!=previous_bank) begin
            if(!frame_done || dut.vcount!=480 || dut.hcount!=1)
                $fatal(1,"Framebuffer changed outside vertical blank");
        end
        previous_bank=dut.front_bank;
        if(!dut.have_frame && {VGA_R,VGA_G,VGA_B}!==24'd0)
            $fatal(1,"Uninitialized framebuffer leaked onto VGA");
        if(dut.have_frame && $isunknown({VGA_R,VGA_G,VGA_B,VGA_HS,VGA_VS}))
            $fatal(1,"Unknown VGA signal after completed frame");
        if(cmd_ready==busy) $fatal(1,"ready/busy invariant");
    end
    task write_command(input [7:0] p,input [31:0] d);
        begin
            @(negedge clk); while(!cmd_ready) @(negedge clk);
            cmd_valid=1;cmd_port=p;cmd_data=d;
            @(negedge clk);cmd_valid=0;
        end
    endtask
    task pixel_expect(input integer x,input integer y,input [7:0] color);
        reg [9:0] actual;
        begin
            actual=dut.front_bank ? dut.framebuffer1[y*320+x] : dut.framebuffer0[y*320+x];
            if(actual[7:0]!==color) $fatal(1,"pixel(%0d,%0d) actual%0d expected%0d",x,y,actual[7:0],color);
        end
    endtask
    task sprite(input integer index,input integer x,input integer y,input integer pat,input integer flags);
        begin
            write_command('h10,index);write_command('h11,x);write_command('h12,y);
            write_command('h13,pat);write_command('h14,flags);
        end
    endtask
    task present;
        integer old_count;
        begin
            old_count=frame_count;
            write_command('hf0,0);
            if(!busy) $fatal(1,"PRESENT did not start renderer");
            wait(frame_count==old_count+1);@(negedge clk);
            if(error) $fatal(1,"Unexpected graphics error during rendering");
        end
    endtask
    initial begin
        #200;@(negedge clk);reset_n=1;
        write_command('h22,255*64);
        for(n=0;n<64;n=n+1) write_command('h23,2);
        write_command('h20,0);
        for(n=0;n<1200;n=n+1) write_command('h21,255);
        write_command('h02,1);
        // Distinct corners test transparency, palette banks, both flips, clipping.
        write_command('h24,250*256);
        for(n=0;n<1024;n=n+1) begin
            if(n==0) write_command('h25,5);
            else if(n==257) write_command('h25,6);
            else if(n==512) write_command('h25,7);
            else if(n==1023) write_command('h25,8);
            else write_command('h25,0);
        end
        write_command('h30,0);write_command('h31,8);write_command('h32,8);
        write_command('h33,28);write_command('h34,28);write_command('h37,11);write_command('h38,3);
        write_command('h30,1);write_command('h31,10);write_command('h32,10);
        write_command('h33,30);write_command('h34,10);write_command('h35,10);write_command('h36,30);
        write_command('h37,12);write_command('h38,3);
        sprite(0,12,12,250,9);sprite(1,12,12,251,9);
        sprite(2,40,40,252,55); // bank1, priority2, H+V flip, enabled
        sprite(3,-15,-15,253,25);
        sprite(4,60,60,250,9);sprite(31,59,60,251,9);
        sprite(5,80,80,250,1); // lower than background -> must be hidden
        present();
        pixel_expect(12,12,5);pixel_expect(13,12,6);pixel_expect(12,13,12);
        pixel_expect(28,28,11);pixel_expect(55,55,23);pixel_expect(40,40,2);
        pixel_expect(0,0,8);pixel_expect(60,60,6);pixel_expect(80,80,2);
        pixel_expect(319,239,2);
        // Read the actual VGA RGB on the falling pixel edge for source (12,12).
        wait(dut.vcount==24 && dut.hcount==25 && !dut.pixel_phase);
        #1;if({VGA_R,VGA_G,VGA_B}!==24'hB59A62) $fatal(1,"RGB/sync RAM pipeline mismatch");
        write_command('h26,5);write_command('h27,24'h123456);
        if(dut.palette1[5]!==24'hB59A62) $fatal(1,"Staging palette changed front frame");
        // Degenerate triangle must not become a filled rectangle.
        write_command('h35,20);write_command('h36,10);
        present();pixel_expect(12,13,11);
        if(dut.palette0[5]!==24'h123456) $fatal(1,"Palette snapshot absent");
        // Full signed-16 coordinate range exercises 35-bit edge arithmetic.
        write_command('h31,-32768);write_command('h32,-32768);
        write_command('h33,32767);write_command('h34,-32768);
        write_command('h35,0);write_command('h36,32767);
        present();pixel_expect(100,100,12);pixel_expect(319,239,12);
        write_command('h31,32767);write_command('h33,-32768);
        present();pixel_expect(100,100,12);pixel_expect(319,239,12);
        // Polygon palette index zero is transparent, even at high priority.
        write_command('h30,0);write_command('h37,0);
        write_command('h30,1);write_command('h37,0);
        present();pixel_expect(100,100,2);pixel_expect(28,28,2);
        write_command('h24,65535);write_command('h25,16);
        if(!error || dut.sprite_memory[65535]!==0) $fatal(1,"Invalid local sprite color was accepted");
        write_command('hf1,0);
        // Invalid address never wraps; following data write must also fail.
        write_command('h20,1200);write_command('h21,1);
        if(!error || dut.tilemap[0]!==255) $fatal(1,"Invalid map address corrupted memory");
        write_command('hf1,0);if(error) $fatal(1,"clear_error failed");
        write_command('h26,255);write_command('h27,24'h010203);write_command('h27,24'hABCDEF);
        if(!error || dut.palette[0]!==0) $fatal(1,"Palette overflow wrapped");
        write_command('hf1,0);write_command('haa,0);
        if(!error) $fatal(1,"Unknown command not reported");
        write_command('hf1,0);write_command('h10,32);write_command('h11,100);
        if(!error || dut.sprite_x[31]!==59) $fatal(1,"Invalid sprite selection corrupted previous sprite");
        write_command('hf1,0);write_command('h30,2);write_command('h31,100);
        if(!error || dut.shape_x0[1]!==32767) $fatal(1,"Invalid shape selection corrupted previous shape");
        $display("PASS tb_gpu_graphics: layers, tie priority, transparency, flips, palette banking/snapshot, signed clipping, both triangle orientations, degenerates, swap, VGA RGB alignment, errors");
        $finish;
    end
    initial begin #150000000; $fatal(1,"Graphics timeout"); end
endmodule
