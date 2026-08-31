module top_de1_soc (

    input  wire       CLOCK_50,
    input  wire [3:0] KEY,

    output wire       VGA_CLK,
    output wire       VGA_HS,
    output wire       VGA_VS,
    output wire       VGA_BLANK_N,
    output wire       VGA_SYNC_N,

    output wire [7:0] VGA_R,
    output wire [7:0] VGA_G,
    output wire [7:0] VGA_B

);

    /*
     * Clock de aproximadamente 25 MHz.
     * O CLOCK_50 da placa é dividido por 2.
     */
    reg pixel_clock;

    always @(posedge CLOCK_50) begin

        if (!KEY[0])
            pixel_clock <= 1'b0;
        else
            pixel_clock <= ~pixel_clock;

    end


    /*
     * Sinais gerados pelo módulo de timing VGA.
     */
    wire       active_video;
    wire [9:0] pixel_x;
    wire [9:0] pixel_y;


    /*
     * Controlador de timing VGA.
     */
    vga_timing timing (

        .clk          (pixel_clock),
        .reset_n      (KEY[0]),

        .hsync        (VGA_HS),
        .vsync        (VGA_VS),

        .active_video (active_video),

        .pixel_x      (pixel_x),
        .pixel_y      (pixel_y)

    );


    /*
     * Conversão da resolução física 640x480
     * para resolução lógica 320x240.
     *
     * Cada pixel lógico ocupa 2x2 pixels físicos.
     */
    wire [8:0] logical_x;
    wire [7:0] logical_y;

    assign logical_x = pixel_x[9:1];
    assign logical_y = pixel_y[8:1];


    /*
     * O background gera um índice de cor
     * de 8 bits.
     */
    wire [7:0] background_color_index;


    /*
     * Motor de Background.
     *
     * Por enquanto não temos scroll.
     */
    background_engine background (

        .clk         (pixel_clock),

        .logical_x   (logical_x),
        .logical_y   (logical_y),

        .color_index (background_color_index)

    );


    /*
     * Sinais RGB gerados pela paleta.
     */
    wire [7:0] background_red;
    wire [7:0] background_green;
    wire [7:0] background_blue;


    /*
     * Conversão:
     *
     * Índice de cor de 8 bits
     *            ↓
     *        Paleta RGB
     */
    palette palette_unit (

        .color_index (background_color_index),

        .red         (background_red),
        .green       (background_green),
        .blue        (background_blue)

    );


    /*
     * Sinais auxiliares VGA.
     */
    assign VGA_CLK     = pixel_clock;

    assign VGA_BLANK_N = active_video;

    assign VGA_SYNC_N  = 1'b0;


    /*
     * Durante a área visível:
     *
     * Background → Paleta → VGA
     *
     * Fora da área visível:
     *
     * Preto.
     */
    assign VGA_R =
        active_video ? background_red : 8'h00;

    assign VGA_G =
        active_video ? background_green : 8'h00;

    assign VGA_B =
        active_video ? background_blue : 8'h00;

endmodule