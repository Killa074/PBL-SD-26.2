// Programmable, double-buffered 320x240 indexed graphics; VGA is 640x480.
// One 50 MHz clock. All RAMs are synchronous; pixel timing uses clock enable.
// PRESENT locks configuration, snapshots the palette, renders and swaps at
// vertical blank. Rendering order resolves equal priority: BG < rect < triangle
// < sprite 0 < ... < sprite 31. Transparent sprites never write depth/color.
module gpu_graphics #(
    parameter TILE_FILE="assets/tiles.hex",
    parameter SPRITE_FILE="assets/sprites.hex",
    parameter TILEMAP_FILE="assets/tilemap.hex",
    parameter PALETTE_FILE="assets/palette.hex"
)(
    input wire clk, input wire reset_n,
    input wire cmd_valid, input wire [7:0] cmd_port,
    input wire [31:0] cmd_data,
    output wire cmd_ready, output wire busy,
    output reg frame_done, output reg error,
    output reg [31:0] frame_count,
    output wire VGA_CLK, output reg VGA_HS, output reg VGA_VS,
    output reg VGA_BLANK_N, output wire VGA_SYNC_N,
    output wire [7:0] VGA_R, VGA_G, VGA_B
);
    localparam IDLE=0, PAL_READ=1, PAL_WRITE=2,
       BG_ADDR=3, BG_TILE=4, BG_WAIT=5, BG_WRITE=6,
       SHAPE_START=7, SHAPE_MUL=8, SHAPE_EDGE=9, DRAW_READ=10,
       DRAW_CHECK=11, SPR_START=12, SPR_READ=13, SPR_CHECK=14, SWAP=15;
    reg [4:0] state;
    assign cmd_ready=(state==IDLE);
    assign busy=(state!=IDLE);

    // Ten bits per pixel: two-bit priority and eight-bit palette index.
    // The display port and render read/write port infer true dual-port M10K.
    (* ramstyle="M10K, no_rw_check" *) reg [9:0] framebuffer0[0:76799];
    (* ramstyle="M10K, no_rw_check" *) reg [9:0] framebuffer1[0:76799];
    (* ramstyle="M10K" *) reg [7:0] tile_memory[0:16383];
    (* ramstyle="M10K" *) reg [7:0] sprite_memory[0:65535];
    (* ramstyle="M10K" *) reg [7:0] tilemap[0:1199];
    (* ramstyle="M10K" *) reg [23:0] palette[0:255];
    (* ramstyle="M10K, no_rw_check" *) reg [23:0] palette0[0:255];
    (* ramstyle="M10K, no_rw_check" *) reg [23:0] palette1[0:255];
    initial begin
        $readmemh(TILE_FILE,tile_memory);
        $readmemh(SPRITE_FILE,sprite_memory);
        $readmemh(TILEMAP_FILE,tilemap);
        $readmemh(PALETTE_FILE,palette);
    end

    reg [8:0] scroll_x;
    reg [7:0] scroll_y;
    reg bg_enable;
    reg [1:0] bg_priority;
    reg [5:0] sprite_select;
    reg signed [15:0] sprite_x[0:31], sprite_y[0:31];
    reg [7:0] sprite_pattern[0:31];
    reg [8:0] sprite_flags[0:31];
    reg [1:0] shape_select;
    reg signed [15:0] shape_x0[0:1],shape_y0[0:1];
    reg signed [15:0] shape_x1[0:1],shape_y1[0:1];
    reg signed [15:0] shape_x2[0:1],shape_y2[0:1];
    reg [7:0] shape_color[0:1];
    reg [2:0] shape_flags[0:1];
    // Extra address bit holds an invalid sentinel after the final valid write.
    reg [10:0] map_write_addr;
    reg [14:0] tile_write_addr;
    reg [16:0] sprite_write_addr;
    reg [8:0] palette_write_addr;
    wire accept=reset_n && cmd_valid && cmd_ready;
    wire map_we=accept && cmd_port==8'h21 && map_write_addr<1200 && cmd_data<256;
    wire tile_we=accept && cmd_port==8'h23 && tile_write_addr<16384 && cmd_data<256;
    // Sprite texels are local 4-bit palette indices, expanded by the bank.
    wire sprite_we=accept && cmd_port==8'h25 && sprite_write_addr<65536 && cmd_data<16;
    wire palette_we=accept && cmd_port==8'h27 && palette_write_addr<256 && cmd_data<32'h01000000;

    reg front_bank,have_frame;
    reg [7:0] copy_index;
    reg [23:0] palette_q;
    reg [8:0] rx;
    reg [7:0] ry;
    wire [16:0] render_addr=({9'b0,ry}<<8)+({9'b0,ry}<<6)+rx;
    reg [7:0] map_q,tile_q,sprite_q;
    reg [13:0] tile_read_addr;
    wire [9:0] bxsum={1'b0,rx}+{1'b0,scroll_x};
    wire [8:0] bysum={1'b0,ry}+{1'b0,scroll_y};
    wire [8:0] bx=bxsum>=320 ? bxsum-320 : bxsum;
    wire [7:0] by=bysum>=240 ? bysum-240 : bysum;
    wire [10:0] map_read_addr=({6'b0,by[7:3]}<<5)+({6'b0,by[7:3]}<<3)+bx[8:3];
    reg [9:0] depth0_q,depth1_q;
    wire [9:0] depth_q=front_bank ? depth0_q : depth1_q;

    reg shape_number;
    reg [8:0] left_x,right_x;
    reg [7:0] top_y,bottom_y;
    reg signed [16:0] dx0,dy0,dx1,dy1,dx2,dy2;
    reg signed [33:0] product00,product01,product10,product11,product20,product21;
    reg signed [34:0] edge0,edge1,edge2,row_edge0,row_edge1,row_edge2;
    reg signed [34:0] area;
    reg signed [33:0] area_product0,area_product1;
    wire signed [16:0] px0=$signed({1'b0,7'b0,rx})-$signed(shape_x0[shape_number]);
    wire signed [16:0] py0=$signed({1'b0,8'b0,ry})-$signed(shape_y0[shape_number]);
    wire signed [16:0] px1=$signed({1'b0,7'b0,rx})-$signed(shape_x1[shape_number]);
    wire signed [16:0] py1=$signed({1'b0,8'b0,ry})-$signed(shape_y1[shape_number]);
    wire signed [16:0] px2=$signed({1'b0,7'b0,rx})-$signed(shape_x2[shape_number]);
    wire signed [16:0] py2=$signed({1'b0,8'b0,ry})-$signed(shape_y2[shape_number]);
    wire triangle_hit=(area>0 && edge0>=0 && edge1>=0 && edge2>=0) ||
                      (area<0 && edge0<=0 && edge1<=0 && edge2<=0);
    wire shape_hit=!shape_number || triangle_hit;
    reg signed [15:0] min_x,max_x,min_y,max_y;
    always @* begin
        min_x=shape_x0[shape_number]; max_x=shape_x0[shape_number];
        min_y=shape_y0[shape_number]; max_y=shape_y0[shape_number];
        if(shape_x1[shape_number]<min_x) min_x=shape_x1[shape_number];
        if(shape_x1[shape_number]>max_x) max_x=shape_x1[shape_number];
        if(shape_y1[shape_number]<min_y) min_y=shape_y1[shape_number];
        if(shape_y1[shape_number]>max_y) max_y=shape_y1[shape_number];
        if(shape_number) begin
            if(shape_x2[1]<min_x) min_x=shape_x2[1];
            if(shape_x2[1]>max_x) max_x=shape_x2[1];
            if(shape_y2[1]<min_y) min_y=shape_y2[1];
            if(shape_y2[1]>max_y) max_y=shape_y2[1];
        end
    end

    reg [4:0] sprite_number;
    reg [3:0] sx,sy;
    wire [3:0] tx=sprite_flags[sprite_number][1] ? 15-sx : sx;
    wire [3:0] ty=sprite_flags[sprite_number][2] ? 15-sy : sy;
    wire [15:0] sprite_read_addr={sprite_pattern[sprite_number],ty,tx};
    wire signed [16:0] screen_sx=$signed(sprite_x[sprite_number])+$signed({13'b0,sx});
    wire signed [16:0] screen_sy=$signed(sprite_y[sprite_number])+$signed({13'b0,sy});
    wire sprite_inside=screen_sx>=0 && screen_sx<320 && screen_sy>=0 && screen_sy<240;
    wire [16:0] sprite_fb_addr=({9'b0,screen_sy[7:0]}<<8)+({9'b0,screen_sy[7:0]}<<6)+screen_sx[8:0];
    wire sprite_render=(state==SPR_READ || state==SPR_CHECK);
    wire [16:0] render_ram_addr=sprite_render ? (sprite_inside ? sprite_fb_addr : 17'd0) : render_addr;
    wire shape_write=state==DRAW_CHECK && shape_hit && shape_color[shape_number]!=0 && shape_flags[shape_number][2:1]>=depth_q[9:8];
    wire sprite_write=state==SPR_CHECK && sprite_inside && sprite_q!=0 &&
                       sprite_flags[sprite_number][4:3]>=depth_q[9:8];
    wire render_we=state==BG_WRITE || shape_write || sprite_write;
    wire [9:0] render_data=(state==BG_WRITE) ?
        (bg_enable ? {bg_priority,tile_q} : 10'd0) :
        (state==DRAW_CHECK) ? {shape_flags[shape_number][2:1],shape_color[shape_number]} :
        {sprite_flags[sprite_number][4:3],sprite_flags[sprite_number][8:5],sprite_q[3:0]};

    // VGA: RAM read on rising VGA phase; palette read/output on falling phase.
    // Thus RGB and sync are stable for half a pixel before the DAC samples.
    reg pixel_phase;
    reg [9:0] hcount,vcount;
    reg sync_h,sync_v,sync_active,scan_bank,scan_have_frame;
    reg [9:0] display0_q,display1_q;
    reg [23:0] rgb0_q,rgb1_q;
    reg output_bank,output_valid;
    wire [16:0] display_addr=(hcount<640 && vcount<480) ?
         (({9'b0,vcount[8:1]}<<8)+({9'b0,vcount[8:1]}<<6)+hcount[9:1]) : 17'd0;
    wire vblank_start=pixel_phase && hcount==0 && vcount==480;
    assign VGA_CLK=pixel_phase;
    assign VGA_SYNC_N=1'b0;
    wire [23:0] rgb=output_bank ? rgb1_q : rgb0_q;
    assign VGA_R=output_valid ? rgb[23:16] : 8'd0;
    assign VGA_G=output_valid ? rgb[15:8] : 8'd0;
    assign VGA_B=output_valid ? rgb[7:0] : 8'd0;

    // Memory blocks have no reset: clearing a large RAM with reset would turn it
    // into flip-flops. have_frame masks the output until a full frame exists.
    always @(posedge clk) begin
        map_q<=tilemap[map_read_addr];
        tile_q<=tile_memory[tile_read_addr];
        sprite_q<=sprite_memory[sprite_read_addr];
        palette_q<=palette[copy_index];
        if(map_we) tilemap[map_write_addr]<=cmd_data[7:0];
        if(tile_we) tile_memory[tile_write_addr]<=cmd_data[7:0];
        if(sprite_we) sprite_memory[sprite_write_addr]<=cmd_data[7:0];
        if(palette_we) palette[palette_write_addr]<=cmd_data[23:0];
        depth0_q<=framebuffer0[render_ram_addr];
        depth1_q<=framebuffer1[render_ram_addr];
        if(render_we) begin
            if(front_bank) framebuffer0[render_ram_addr]<=render_data;
            else framebuffer1[render_ram_addr]<=render_data;
        end
        if(state==PAL_WRITE) begin
            if(front_bank) palette0[copy_index]<=palette_q;
            else palette1[copy_index]<=palette_q;
        end
        if(!pixel_phase) begin
            display0_q<=framebuffer0[display_addr];
            display1_q<=framebuffer1[display_addr];
        end else begin
            rgb0_q<=palette0[display0_q[7:0]];
            rgb1_q<=palette1[display1_q[7:0]];
        end
    end

    always @(posedge clk) begin
        if(!reset_n) begin
            pixel_phase<=0; hcount<=0; vcount<=0;
            sync_h<=1; sync_v<=1; sync_active<=0;
            scan_bank<=0; scan_have_frame<=0;
            VGA_HS<=1; VGA_VS<=1; VGA_BLANK_N<=0;
            output_bank<=0; output_valid<=0;
        end else begin
            pixel_phase<=~pixel_phase;
            if(!pixel_phase) begin
                sync_h<=!(hcount>=656 && hcount<752);
                sync_v<=!(vcount>=490 && vcount<492);
                sync_active<=hcount<640 && vcount<480;
                scan_bank<=front_bank; scan_have_frame<=have_frame;
            end else begin
                VGA_HS<=sync_h; VGA_VS<=sync_v; VGA_BLANK_N<=sync_active;
                output_bank<=scan_bank; output_valid<=sync_active && scan_have_frame;
                if(hcount==799) begin
                    hcount<=0;
                    if(vcount==524) vcount<=0; else vcount<=vcount+1'b1;
                end else hcount<=hcount+1'b1;
            end
        end
    end

    integer i;
    always @(posedge clk) begin
        if(!reset_n) begin
            state<=IDLE; front_bank<=0; have_frame<=0; frame_done<=0;
            frame_count<=0; error<=0; scroll_x<=0; scroll_y<=0;
            bg_enable<=1; bg_priority<=0; sprite_select<=0; shape_select<=0;
            map_write_addr<=0; tile_write_addr<=0; sprite_write_addr<=0; palette_write_addr<=0;
            copy_index<=0; rx<=0; ry<=0; tile_read_addr<=0;
            sprite_number<=0; sx<=0; sy<=0; shape_number<=0;
            left_x<=0; right_x<=0; top_y<=0; bottom_y<=0;
            dx0<=0;dy0<=0;dx1<=0;dy1<=0;dx2<=0;dy2<=0;
            product00<=0;product01<=0;product10<=0;product11<=0;product20<=0;product21<=0;
            area_product0<=0;area_product1<=0;area<=0;
            edge0<=0;edge1<=0;edge2<=0;row_edge0<=0;row_edge1<=0;row_edge2<=0;
            for(i=0;i<32;i=i+1) begin
                sprite_x[i]<=0;sprite_y[i]<=0;sprite_pattern[i]<=0;sprite_flags[i]<=0;
            end
            for(i=0;i<2;i=i+1) begin
                shape_x0[i]<=0;shape_y0[i]<=0;shape_x1[i]<=0;shape_y1[i]<=0;
                shape_x2[i]<=0;shape_y2[i]<=0;shape_color[i]<=0;shape_flags[i]<=0;
            end
        end else begin
            frame_done<=0;
            case(state)
                IDLE: if(cmd_valid) begin
                    case(cmd_port)
                        8'h00: if(cmd_data<320) scroll_x<=cmd_data[8:0]; else error<=1;
                        8'h01: if(cmd_data<240) scroll_y<=cmd_data[7:0]; else error<=1;
                        8'h02: if(cmd_data<4) bg_priority<=cmd_data[1:0]; else error<=1;
                        8'h03: if(cmd_data<2) bg_enable<=cmd_data[0]; else error<=1;
                        8'h10: if(cmd_data<32) sprite_select<=cmd_data[5:0]; else begin sprite_select<=32;error<=1;end
                        8'h11: if(sprite_select<32) sprite_x[sprite_select]<=cmd_data[15:0]; else error<=1;
                        8'h12: if(sprite_select<32) sprite_y[sprite_select]<=cmd_data[15:0]; else error<=1;
                        8'h13: if(sprite_select<32 && cmd_data<256) sprite_pattern[sprite_select]<=cmd_data[7:0]; else error<=1;
                        8'h14: if(sprite_select<32 && cmd_data<512) sprite_flags[sprite_select]<=cmd_data[8:0]; else error<=1;
                        8'h20: if(cmd_data<1200) map_write_addr<=cmd_data[10:0]; else begin map_write_addr<=1200;error<=1;end
                        8'h21: if(map_we) map_write_addr<=map_write_addr+1'b1; else error<=1;
                        8'h22: if(cmd_data<16384) tile_write_addr<=cmd_data[14:0]; else begin tile_write_addr<=16384;error<=1;end
                        8'h23: if(tile_we) tile_write_addr<=tile_write_addr+1'b1; else error<=1;
                        8'h24: if(cmd_data<65536) sprite_write_addr<=cmd_data[16:0]; else begin sprite_write_addr<=65536;error<=1;end
                        8'h25: if(sprite_we) sprite_write_addr<=sprite_write_addr+1'b1; else error<=1;
                        8'h26: if(cmd_data<256) palette_write_addr<=cmd_data[8:0]; else begin palette_write_addr<=256;error<=1;end
                        8'h27: if(palette_we) palette_write_addr<=palette_write_addr+1'b1; else error<=1;
                        8'h30: if(cmd_data<2) shape_select<=cmd_data[1:0]; else begin shape_select<=2;error<=1;end
                        8'h31: if(shape_select<2) shape_x0[shape_select]<=cmd_data[15:0]; else error<=1;
                        8'h32: if(shape_select<2) shape_y0[shape_select]<=cmd_data[15:0]; else error<=1;
                        8'h33: if(shape_select<2) shape_x1[shape_select]<=cmd_data[15:0]; else error<=1;
                        8'h34: if(shape_select<2) shape_y1[shape_select]<=cmd_data[15:0]; else error<=1;
                        8'h35: if(shape_select<2) shape_x2[shape_select]<=cmd_data[15:0]; else error<=1;
                        8'h36: if(shape_select<2) shape_y2[shape_select]<=cmd_data[15:0]; else error<=1;
                        8'h37: if(shape_select<2 && cmd_data<256) shape_color[shape_select]<=cmd_data[7:0]; else error<=1;
                        8'h38: if(shape_select<2 && cmd_data<8) shape_flags[shape_select]<=cmd_data[2:0]; else error<=1;
                        8'hf0: begin copy_index<=0;state<=PAL_READ;end
                        8'hf1: error<=0;
                        default:error<=1;
                    endcase
                end
                PAL_READ: state<=PAL_WRITE;
                PAL_WRITE: if(copy_index==255) begin rx<=0;ry<=0;state<=BG_ADDR;end
                           else begin copy_index<=copy_index+1'b1;state<=PAL_READ;end
                BG_ADDR: state<=BG_TILE;
                BG_TILE: begin tile_read_addr<={map_q,by[2:0],bx[2:0]};state<=BG_WAIT;end
                BG_WAIT: state<=BG_WRITE;
                BG_WRITE: begin
                    if(rx==319) begin
                        rx<=0;
                        if(ry==239) begin shape_number<=0;state<=SHAPE_START;end
                        else begin ry<=ry+1'b1;state<=BG_ADDR;end
                    end else begin rx<=rx+1'b1;state<=BG_ADDR;end
                end
                SHAPE_START: begin
                    if(!shape_flags[shape_number][0] || shape_color[shape_number]==0 || max_x<0 || min_x>319 || max_y<0 || min_y>239) begin
                        if(!shape_number) begin shape_number<=1;state<=SHAPE_START;end
                        else begin sprite_number<=0;state<=SPR_START;end
                    end else begin
                        left_x<=min_x<0 ? 0 : min_x[8:0]; rx<=min_x<0 ? 0 : min_x[8:0];
                        right_x<=max_x>319 ? 319 : max_x[8:0];
                        top_y<=min_y<0 ? 0 : min_y[7:0]; ry<=min_y<0 ? 0 : min_y[7:0];
                        bottom_y<=max_y>239 ? 239 : max_y[7:0];
                        dx0<=$signed(shape_x1[shape_number])-$signed(shape_x0[shape_number]);
                        dy0<=$signed(shape_y1[shape_number])-$signed(shape_y0[shape_number]);
                        dx1<=$signed(shape_x2[shape_number])-$signed(shape_x1[shape_number]);
                        dy1<=$signed(shape_y2[shape_number])-$signed(shape_y1[shape_number]);
                        dx2<=$signed(shape_x0[shape_number])-$signed(shape_x2[shape_number]);
                        dy2<=$signed(shape_y0[shape_number])-$signed(shape_y2[shape_number]);
                        state<=SHAPE_MUL;
                    end
                end
                SHAPE_MUL: begin
                    product00<=dx0*py0;product01<=dy0*px0;
                    product10<=dx1*py1;product11<=dy1*px1;
                    product20<=dx2*py2;product21<=dy2*px2;
                    area_product0<=dx0*(-dy2);area_product1<=dy0*(-dx2);
                    state<=SHAPE_EDGE;
                end
                SHAPE_EDGE: begin
                    edge0<=$signed(product00)-$signed(product01);row_edge0<=$signed(product00)-$signed(product01);
                    edge1<=$signed(product10)-$signed(product11);row_edge1<=$signed(product10)-$signed(product11);
                    edge2<=$signed(product20)-$signed(product21);row_edge2<=$signed(product20)-$signed(product21);
                    area<=$signed(area_product0)-$signed(area_product1);
                    if(shape_number && area_product0==area_product1) begin sprite_number<=0;state<=SPR_START;end
                    else state<=DRAW_READ;
                end
                DRAW_READ: state<=DRAW_CHECK;
                DRAW_CHECK: begin
                    if(rx==right_x) begin
                        rx<=left_x;
                        if(ry==bottom_y) begin
                            if(!shape_number) begin shape_number<=1;state<=SHAPE_START;end
                            else begin sprite_number<=0;state<=SPR_START;end
                        end else begin
                            ry<=ry+1'b1;
                            row_edge0<=row_edge0+dx0;edge0<=row_edge0+dx0;
                            row_edge1<=row_edge1+dx1;edge1<=row_edge1+dx1;
                            row_edge2<=row_edge2+dx2;edge2<=row_edge2+dx2;
                            state<=DRAW_READ;
                        end
                    end else begin
                        rx<=rx+1'b1;edge0<=edge0-dy0;edge1<=edge1-dy1;edge2<=edge2-dy2;state<=DRAW_READ;
                    end
                end
                SPR_START: begin
                    sx<=0;sy<=0;
                    if(sprite_flags[sprite_number][0]) state<=SPR_READ;
                    else if(sprite_number==31) state<=SWAP;
                    else sprite_number<=sprite_number+1'b1;
                end
                SPR_READ: state<=SPR_CHECK;
                SPR_CHECK: begin
                    if(sx==15) begin
                        sx<=0;
                        if(sy==15) begin
                            if(sprite_number==31) state<=SWAP;
                            else begin sprite_number<=sprite_number+1'b1;state<=SPR_START;end
                        end else begin sy<=sy+1'b1;state<=SPR_READ;end
                    end else begin sx<=sx+1'b1;state<=SPR_READ;end
                end
                SWAP: if(vblank_start) begin
                    front_bank<=~front_bank;have_frame<=1;frame_count<=frame_count+1'b1;
                    frame_done<=1;state<=IDLE;
                end
                default: begin state<=IDLE;error<=1;end
            endcase
        end
    end
endmodule
