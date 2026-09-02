module top_de1_soc (

    input  wire       CLOCK_50,
    input  wire [3:0] KEY,
    input  wire [9:0] SW,

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
     * CLOCK_50 / 2 = aproximadamente 25 MHz
     *
     * KEY[0] = RESET
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
     * Cena:
     * 320 x 240
     *
     * Cada pixel lógico vira 2x2 pixels físicos.
     */

    wire [8:0] logical_x;
    wire [7:0] logical_y;

    assign logical_x = pixel_x[9:1];
    assign logical_y = pixel_y[8:1];


    /*
     * =====================================================
     * SCROLL
     * =====================================================
     *
     * KEY[2] = movimentar
     *
     * SW[2:0]:
     *
     * 000 = direita
     * 001 = esquerda
     * 011 = cima
     * 111 = baixo
     */

    reg [8:0] scroll_x;
    reg [7:0] scroll_y;

    reg [17:0] scroll_counter;


    always @(posedge pixel_clock) begin

        if (!KEY[0]) begin

            scroll_x <= 9'd0;
            scroll_y <= 8'd0;

            scroll_counter <= 18'd0;

        end

        else begin

            /*
             * KEY[2] pressionado.
             * KEY é ativo em nível baixo.
             */

            if (!KEY[2]) begin

                if (scroll_counter == 18'd249999) begin

                    scroll_counter <= 18'd0;


                    case (SW[2:0])


                        /*
                         * DIREITA
                         */
                        3'b000: begin

                            if (scroll_x == 9'd319)
                                scroll_x <= 9'd0;
                            else
                                scroll_x <= scroll_x + 1'b1;

                        end


                        /*
                         * ESQUERDA
                         */
                        3'b001: begin

                            if (scroll_x == 9'd0)
                                scroll_x <= 9'd319;
                            else
                                scroll_x <= scroll_x - 1'b1;

                        end


                        /*
                         * CIMA
                         */
                        3'b011: begin

                            if (scroll_y == 8'd0)
                                scroll_y <= 8'd239;
                            else
                                scroll_y <= scroll_y - 1'b1;

                        end


                        /*
                         * BAIXO
                         */
                        3'b111: begin

                            if (scroll_y == 8'd239)
                                scroll_y <= 8'd0;
                            else
                                scroll_y <= scroll_y + 1'b1;

                        end


                        /*
                         * Combinação inválida:
                         * fica parado.
                         */
                        default: begin

                            scroll_x <= scroll_x;
                            scroll_y <= scroll_y;

                        end

                    endcase

                end

                else begin

                    scroll_counter <=
                        scroll_counter + 1'b1;

                end

            end

            else begin

                scroll_counter <= 18'd0;

            end

        end

    end


    /*
     * =====================================================
     * ALTERAÇÃO DINÂMICA DO TILEMAP
     * =====================================================
     *
     * KEY[1]
     *
     * Região 6x6:
     *
     * Tile 0 <-> Tile 7
     */

    localparam TILE_NORMAL   = 8'd0;
    localparam TILE_ALTERADO = 8'd7;


    localparam STATE_WAIT_PRESS   = 2'd0;
    localparam STATE_WRITE        = 2'd1;
    localparam STATE_WAIT_RELEASE = 2'd2;


    reg [1:0] state;

    reg [2:0] patch_x;
    reg [2:0] patch_y;

    reg patch_mode;

    reg [17:0] release_counter;


    /*
     * Região começa em:
     *
     * tile X = 16
     * tile Y = 18
     */

    wire [5:0] patch_map_x;
    wire [4:0] patch_map_y;

    assign patch_map_x =
        6'd16 + patch_x;

    assign patch_map_y =
        5'd18 + patch_y;


    wire [10:0] patch_y_extended;
    wire [10:0] patch_x_extended;

    assign patch_y_extended =
        {6'd0, patch_map_y};

    assign patch_x_extended =
        {5'd0, patch_map_x};


    /*
     * endereço = y * 40 + x
     *
     * 40 = 32 + 8
     */

    wire [10:0] tilemap_write_address;

    assign tilemap_write_address =

        (patch_y_extended << 5)

        +

        (patch_y_extended << 3)

        +

        patch_x_extended;


    wire tilemap_write_enable;

    assign tilemap_write_enable =
        (state == STATE_WRITE);


    wire [7:0] tilemap_write_data;

    assign tilemap_write_data =

        patch_mode

        ? TILE_ALTERADO

        : TILE_NORMAL;


    /*
     * FSM de alteração do tilemap.
     */

    always @(posedge pixel_clock) begin

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
                 * Espera KEY[1].
                 */
                STATE_WAIT_PRESS: begin

                    if (!KEY[1]) begin

                        patch_mode <= ~patch_mode;

                        patch_x <= 3'd0;
                        patch_y <= 3'd0;

                        state <= STATE_WRITE;

                    end

                end


                /*
                 * Escreve a região 6x6.
                 */
                STATE_WRITE: begin

                    if (patch_x == 3'd5) begin

                        patch_x <= 3'd0;

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
                 * Espera KEY[1] ser solto.
                 */
                STATE_WAIT_RELEASE: begin

                    if (!KEY[1]) begin

                        release_counter <= 18'd0;

                    end

                    else begin

                        if (
                            release_counter ==
                            18'd249999
                        ) begin

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

        .scroll_x              (scroll_x),
        .scroll_y              (scroll_y),

        .tilemap_write_enable  (
            tilemap_write_enable
        ),

        .tilemap_write_address (
            tilemap_write_address
        ),

        .tilemap_write_data    (
            tilemap_write_data
        ),

        .color_index (
            background_color_index
        )

    );


    /*
     * =====================================================
     * SPRITE ENGINE
     * =====================================================
     *
     * Sprite 0:
     *
     * posição X = 152
     * posição Y = 112
     *
     * Como possui 16x16:
     * fica centralizado na tela 320x240.
     *
     *
     * SW[3] = flip horizontal
     * SW[4] = flip vertical
     */


    wire [7:0] sprite_color_index;

    wire       sprite_visible;

    wire [1:0] sprite_pixel_priority;


    sprite_engine sprites (

        .clk       (pixel_clock),
        .reset_n   (KEY[0]),

        .logical_x (logical_x),
        .logical_y (logical_y),


        /*
         * =================================================
         * ATRIBUTOS DO SPRITE 0
         * =================================================
         *
         * Mantemos write_enable ligado.
         *
         * Assim os switches SW3/SW4 conseguem
         * modificar o flip em tempo real.
         */

        .attr_write_enable (
            1'b1
        ),


        /*
         * Sprite número 0.
         */

        .attr_write_index (
            5'd0
        ),


        /*
         * Posição central.
         */

        .attr_write_x (
            9'd152
        ),

        .attr_write_y (
            8'd112
        ),


        /*
         * Pattern 0 = sprite.hex.
         */

        .attr_write_pattern (
            8'd0
        ),


        /*
         * Sprite ligado.
         */

        .attr_write_sprite_enable (
            1'b1
        ),


        /*
         * Prioridade alta.
         */

        .attr_write_priority (
            2'd3
        ),


        /*
         * ===============================================
         * FLIP
         * ===============================================
         *
         * SW3:
         * horizontal
         *
         * SW4:
         * vertical
         */

        .attr_write_hflip (
            SW[3]
        ),

        .attr_write_vflip (
            SW[4]
        ),


        /*
         * O sprite.hex já contém índices globais
         * da palette_with_sprite.hex.
         *
         * O atributo existe, mas ainda não fazemos
         * remapeamento de banco de paleta.
         */

        .attr_write_palette (
            4'd0
        ),


        /*
         * Saídas.
         */

        .color_index (
            sprite_color_index
        ),

        .pixel_visible (
            sprite_visible
        ),

        .pixel_priority (
            sprite_pixel_priority
        )

    );
	 
	     /*
     * =====================================================
     * POLYGON ENGINE
     * =====================================================
     *
     * Retangulo:
     *
     * X = 30 ate 99
     * Y = 30 ate 79
     *
     * Cor = indice 21
     * (marrom da palette_with_sprite.hex)
     *
     *
     * Triangulo:
     *
     * A = (160,30)
     * B = (120,100)
     * C = (210,100)
     *
     * Cor = indice 22
     * (bege da palette_with_sprite.hex)
     */


    wire [7:0] polygon_color_index;

    wire       polygon_visible;

    wire [1:0] polygon_pixel_priority;


    polygon_engine polygons (

        .logical_x (
            logical_x
        ),

        .logical_y (
            logical_y
        ),


        /*
         * ===============================================
         * RETANGULO
         * ===============================================
         */

        .rect_enable (
            1'b1
        ),

        .rect_x0 (
            9'd30
        ),

        .rect_y0 (
            8'd30
        ),

        .rect_x1 (
            9'd100
        ),

        .rect_y1 (
            8'd80
        ),

        /*
         * Marrom.
         */
        .rect_color (
            8'd21
        ),

        /*
         * Prioridade interna entre poligonos.
         */
        .rect_priority (
            2'd1
        ),


        /*
         * ===============================================
         * TRIANGULO
         * ===============================================
         */

        .tri_enable (
            1'b1
        ),

        /*
         * Vertice A
         */
        .tri_x0 (
            9'd160
        ),

        .tri_y0 (
            8'd30
        ),


        /*
         * Vertice B
         */
        .tri_x1 (
            9'd120
        ),

        .tri_y1 (
            8'd100
        ),


        /*
         * Vertice C
         */
        .tri_x2 (
            9'd210
        ),

        .tri_y2 (
            8'd100
        ),


        /*
         * Bege.
         */
        .tri_color (
            8'd22
        ),

        /*
         * Triangulo ganha do retangulo
         * se houver sobreposicao.
         */
        .tri_priority (
            2'd2
        ),


        /*
         * Saidas.
         */

        .color_index (
            polygon_color_index
        ),

        .pixel_visible (
            polygon_visible
        ),

        .pixel_priority (
            polygon_pixel_priority
        )

    );
	 
	 


    /*
     * =====================================================
     * COMPOSITOR
     * =====================================================
     *
     * Por enquanto temos duas camadas:
     *
     * 1º SPRITE
     * 2º BACKGROUND
     *
     *
     * sprite_visible só fica 1 quando:
     *
     * - existe sprite naquele pixel
     * - o sprite está habilitado
     * - o pixel NÃO é cor 0
     *
     *
     * Logo:
     *
     * cor 0 = transparente.
     */

        wire [7:0] final_color_index;


    /*
     * =====================================================
     * PRIORIDADE DAS CAMADAS
     * =====================================================
     *
     * 1 - Sprite
     * 2 - Poligono
     * 3 - Background
     *
     * A transparencia ja foi aplicada antes:
     *
     * sprite_visible  = 0 se pixel do sprite for 0
     * polygon_visible = 0 se nao houver poligono
     */

    assign final_color_index =

        sprite_visible

        ? sprite_color_index

        :

        polygon_visible

        ? polygon_color_index

        :

        background_color_index;


    /*
     * =====================================================
     * PALETA
     * =====================================================
     *
     * IMPORTANTE:
     *
     * palette.v precisa estar lendo:
     *
     * palette_with_sprite.hex
     */

    wire [7:0] final_red;
    wire [7:0] final_green;
    wire [7:0] final_blue;


    palette palette_unit (

        .color_index (
            final_color_index
        ),

        .red (
            final_red
        ),

        .green (
            final_green
        ),

        .blue (
            final_blue
        )

    );


    /*
     * =====================================================
     * VGA
     * =====================================================
     */

    assign VGA_CLK =
        pixel_clock;

    assign VGA_BLANK_N =
        active_video;

    assign VGA_SYNC_N =
        1'b0;


    assign VGA_R =

        active_video

        ? final_red

        : 8'h00;


    assign VGA_G =

        active_video

        ? final_green

        : 8'h00;


    assign VGA_B =

        active_video

        ? final_blue

        : 8'h00;


endmodule