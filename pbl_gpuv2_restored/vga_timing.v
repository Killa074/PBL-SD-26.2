module vga_timing (
    input  wire       clk,
    input  wire       reset_n,

    output wire       hsync,
    output wire       vsync,
    output wire       active_video,
    output wire [9:0] pixel_x,
    output wire [9:0] pixel_y
);

    // Timing VGA 640x480, aproximadamente 60 Hz
    localparam H_VISIBLE = 640;
    localparam H_FRONT   = 16;
    localparam H_SYNC    = 96;
    localparam H_BACK    = 48;
    localparam H_TOTAL   = 800;

    localparam V_VISIBLE = 480;
    localparam V_FRONT   = 10;
    localparam V_SYNC    = 2;
    localparam V_BACK    = 33;
    localparam V_TOTAL   = 525;

    reg [9:0] h_count;
    reg [9:0] v_count;

    // Conta pixels e linhas
    always @(posedge clk) begin
        if (!reset_n) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end else begin
            if (h_count == H_TOTAL - 1) begin
                h_count <= 10'd0;

                if (v_count == V_TOTAL - 1)
                    v_count <= 10'd0;
                else
                    v_count <= v_count + 1'b1;
            end else begin
                h_count <= h_count + 1'b1;
            end
        end
    end

    // A imagem só é exibida na área visível de 640x480
    assign active_video = (h_count < H_VISIBLE) &&
                          (v_count < V_VISIBLE);

    // Sincronismos VGA ativos em nível baixo
    assign hsync = !((h_count >= H_VISIBLE + H_FRONT) &&
                     (h_count <  H_VISIBLE + H_FRONT + H_SYNC));

    assign vsync = !((v_count >= V_VISIBLE + V_FRONT) &&
                     (v_count <  V_VISIBLE + V_FRONT + V_SYNC));

    assign pixel_x = h_count;
    assign pixel_y = v_count;

endmodule