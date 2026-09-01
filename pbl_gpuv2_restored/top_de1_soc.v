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
     * =====================================================
     * CLOCK VGA
     * =====================================================
     *
     * Divide 50 MHz por 2.
     *
     * KEY[0] continua sendo RESET.
     */

    reg pixel_clock;

    always @(posedge CLOCK_50) begin

        if (!KEY[0])
            pixel_clock <= 1'b0;

        else
            pixel_clock <= ~pixel_clock;

    end


    /*
     * =====================================================
     * VGA TIMING
     * =====================================================
     */

    wire       active_video;

    wire [9:0] pixel_x;
    wire [9:0] pixel_y;


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
     * =====================================================
     * RESOLUÇÃO LÓGICA
     * =====================================================
     *
     * VGA:
     * 640 x 480
     *
     * Jogo:
     * 320 x 240
     *
     * Cada pixel lógico vira 2x2.
     */

    wire [8:0] logical_x;
    wire [7:0] logical_y;

    assign logical_x = pixel_x[9:1];
    assign logical_y = pixel_y[8:1];


    /*
     * =====================================================
     * DEMONSTRAÇÃO DE ESCRITA NO TILEMAP
     * =====================================================
     *
     * KEY[1]:
     *
     * alterna uma região 6x6 entre:
     *
     * Tile 0 = verde claro
     * Tile 7 = verde escuro
     *
     *
     * Região:
     *
     * X = 16 até 21
     * Y = 18 até 23
     *
     *
     * Essa região do mapa atual é originalmente
     * formada por Tile 0.
     */


    localparam TILE_NORMAL = 8'd0;
    localparam TILE_ALTERADO = 8'd7;


    /*
     * Estado 0:
     * esperando botão.
     *
     * Estado 1:
     * escrevendo os 36 tiles.
     *
     * Estado 2:
     * esperando o botão ser solto.
     */

    localparam STATE_WAIT_PRESS   = 2'd0;
    localparam STATE_WRITE        = 2'd1;
    localparam STATE_WAIT_RELEASE = 2'd2;


    reg [1:0] state;


    /*
     * Posição dentro da região 6x6.
     */

    reg [2:0] patch_x;
    reg [2:0] patch_y;


    /*
     * 0 = Tile 0
     * 1 = Tile 7
     */

    reg patch_mode;


    /*
     * Contador usado para garantir que
     * o botão realmente foi solto.
     *
     * Evita múltiplas ativações por bounce.
     */
    reg [17:0] release_counter;


    /*
     * =====================================================
     * ENDEREÇO DE ESCRITA
     * =====================================================
     */

    wire [5:0] patch_map_x;
    wire [4:0] patch_map_y;

    assign patch_map_x =
        6'd16 + patch_x;

    assign patch_map_y =
        5'd18 + patch_y;


    /*
     * Extensão para 11 bits.
     */

    wire [10:0] patch_y_extended;
    wire [10:0] patch_x_extended;

    assign patch_y_extended =
        {6'd0, patch_map_y};

    assign patch_x_extended =
        {5'd0, patch_map_x};


    /*
     * Endereço:
     *
     * y * 40 + x
     */

    wire [10:0] tilemap_write_address;

    assign tilemap_write_address =

        (patch_y_extended << 5) +

        (patch_y_extended << 3) +

        patch_x_extended;


    /*
     * Só escreve enquanto a FSM estiver
     * no estado STATE_WRITE.
     */

    wire tilemap_write_enable;

    assign tilemap_write_enable =
        (state == STATE_WRITE);


    /*
     * Dado que será escrito.
     */

    wire [7:0] tilemap_write_data;

    assign tilemap_write_data =
        patch_mode
        ? TILE_ALTERADO
        : TILE_NORMAL;


    /*
     * =====================================================
     * FSM DE ALTERAÇÃO DO TILEMAP
     * =====================================================
     */

    always @(posedge pixel_clock) begin

        /*
         * KEY[0] = RESET
         */

        if (!KEY[0]) begin

            state <= STATE_WAIT_PRESS;

            patch_x <= 3'd0;
            patch_y <= 3'd0;

            patch_mode <= 1'b0;

            release_counter <= 18'd0;

        end

        else begin

            case (state)


                /*
                 * -----------------------------------------
                 * ESPERANDO KEY[1]
                 * -----------------------------------------
                 *
                 * KEY é ativo em nível baixo.
                 */

                STATE_WAIT_PRESS: begin

                    if (!KEY[1]) begin

                        /*
                         * Alterna:
                         *
                         * Tile 0 <-> Tile 7
                         */

                        patch_mode <= ~patch_mode;


                        /*
                         * Começa pelo primeiro tile
                         * da região.
                         */

                        patch_x <= 3'd0;
                        patch_y <= 3'd0;


                        state <= STATE_WRITE;

                    end

                end


                /*
                 * -----------------------------------------
                 * ESCREVENDO REGIÃO 6x6
                 * -----------------------------------------
                 *
                 * Uma posição é escrita por clock.
                 */

                STATE_WRITE: begin


                    /*
                     * Terminou uma linha?
                     */

                    if (patch_x == 3'd5) begin

                        patch_x <= 3'd0;


                        /*
                         * Terminou a última linha?
                         */

                        if (patch_y == 3'd5) begin

                            patch_y <= 3'd0;

                            release_counter <= 18'd0;

                            state <= STATE_WAIT_RELEASE;

                        end

                        else begin

                            patch_y <= patch_y + 1'b1;

                        end

                    end

                    else begin

                        patch_x <= patch_x + 1'b1;

                    end

                end


                /*
                 * -----------------------------------------
                 * ESPERANDO KEY[1] SER SOLTO
                 * -----------------------------------------
                 *
                 * Esperamos aproximadamente 10 ms
                 * com o botão solto.
                 *
                 * Isso ajuda contra bounce.
                 */

                STATE_WAIT_RELEASE: begin

                    /*
                     * KEY[1] ainda pressionado.
                     */

                    if (!KEY[1]) begin

                        release_counter <= 18'd0;

                    end

                    else begin

                        /*
                         * 250000 clocks em 25 MHz
                         * ≈ 10 ms
                         */

                        if (release_counter == 18'd249999) begin

                            release_counter <= 18'd0;

                            state <= STATE_WAIT_PRESS;

                        end

                        else begin

                            release_counter <=
                                release_counter + 1'b1;

                        end

                    end

                end


                default: begin

                    state <= STATE_WAIT_PRESS;

                end

            endcase

        end

    end


    /*
     * =====================================================
     * BACKGROUND ENGINE
     * =====================================================
     */

    wire [7:0] background_color_index;


    background_engine background (

        .clk                   (pixel_clock),

        .logical_x             (logical_x),
        .logical_y             (logical_y),

        .tilemap_write_enable  (tilemap_write_enable),
        .tilemap_write_address (tilemap_write_address),
        .tilemap_write_data    (tilemap_write_data),

        .color_index           (background_color_index)

    );


    /*
     * =====================================================
     * PALETA
     * =====================================================
     */

    wire [7:0] background_red;
    wire [7:0] background_green;
    wire [7:0] background_blue;


    palette palette_unit (

        .color_index (background_color_index),

        .red         (background_red),
        .green       (background_green),
        .blue        (background_blue)

    );


    /*
     * =====================================================
     * VGA
     * =====================================================
     */

    assign VGA_CLK = pixel_clock;

    assign VGA_BLANK_N = active_video;

    assign VGA_SYNC_N = 1'b0;


    assign VGA_R =
        active_video
        ? background_red
        : 8'h00;


    assign VGA_G =
        active_video
        ? background_green
        : 8'h00;


    assign VGA_B =
        active_video
        ? background_blue
        : 8'h00;


endmodule