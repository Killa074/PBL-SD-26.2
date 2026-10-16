// Common core for the button-driven demonstration and the HPS top-level.
module gpu_system (
    input wire clk, input wire reset_n, input wire demo_start,
    input wire [5:0] avs_address,
    input wire avs_read, input wire avs_write,
    input wire [31:0] avs_writedata,
    output wire [31:0] avs_readdata,
    output wire avs_waitrequest,
    output wire VGA_CLK, VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N,
    output wire [7:0] VGA_R, VGA_G, VGA_B
);
    wire command_valid, command_ready;
    wire [7:0] command_port;
    wire [31:0] command_data;
    wire graphics_busy, graphics_done, graphics_error;
    wire [31:0] frame_count;
    gpu_host host (
        .clk(clk), .reset_n(reset_n), .demo_start(demo_start),
        .avs_address(avs_address), .avs_read(avs_read), .avs_write(avs_write),
        .avs_writedata(avs_writedata), .avs_readdata(avs_readdata),
        .avs_waitrequest(avs_waitrequest),
        .gfx_valid(command_valid), .gfx_ready(command_ready),
        .gfx_port(command_port), .gfx_data(command_data),
        .gfx_busy(graphics_busy), .gfx_done(graphics_done),
        .gfx_error(graphics_error), .gfx_frame_count(frame_count)
    );
    gpu_graphics graphics (
        .clk(clk), .reset_n(reset_n),
        .cmd_valid(command_valid), .cmd_ready(command_ready),
        .cmd_port(command_port), .cmd_data(command_data),
        .busy(graphics_busy), .frame_done(graphics_done),
        .error(graphics_error), .frame_count(frame_count),
        .VGA_CLK(VGA_CLK), .VGA_HS(VGA_HS), .VGA_VS(VGA_VS),
        .VGA_BLANK_N(VGA_BLANK_N), .VGA_SYNC_N(VGA_SYNC_N),
        .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B)
    );
endmodule
