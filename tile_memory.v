module tile_memory (

    input wire [7:0] tile_index,
    input wire [2:0] pixel_x,
    input wire [2:0] pixel_y,

    output reg [7:0] color_index

);

    /*
     * 256 tiles possíveis.
     *
     * Cada tile possui:
     * 8 x 8 = 64 pixels
     *
     * Total:
     * 256 x 64 = 16384 posições.
     */
    reg [7:0] memory [0:16383];

    integer i;


    initial begin

        /*
         * =====================================================
         * TILE 0 - ÁGUA
         * =====================================================
         *
         * Endereços 0 até 63
         *
         * Usamos duas cores para criar um pequeno padrão
         * visual de água.
         */

        for (i = 0; i < 64; i = i + 1) begin

            if (
                ((i % 8) == 1 && (i / 8) == 2) ||
                ((i % 8) == 5 && (i / 8) == 5)
            )
                memory[i] = 8'd11;
            else
                memory[i] = 8'd10;

        end


        /*
         * =====================================================
         * TILE 1 - GRAMA
         * =====================================================
         *
         * Endereços 64 até 127
         *
         * Verde principal com alguns pixels diferentes
         * para dar textura.
         */

        for (i = 0; i < 64; i = i + 1) begin

            if (
                ((i % 8) == 2 && (i / 8) == 1) ||
                ((i % 8) == 6 && (i / 8) == 4) ||
                ((i % 8) == 3 && (i / 8) == 6)
            )
                memory[64 + i] = 8'd21;
            else
                memory[64 + i] = 8'd20;

        end


        /*
         * =====================================================
         * TILE 2 - TERRA / CAMINHO
         * =====================================================
         *
         * Endereços 128 até 191
         *
         * Marrom principal com textura.
         */

        for (i = 0; i < 64; i = i + 1) begin

            if (
                ((i % 8) == 1 && (i / 8) == 1) ||
                ((i % 8) == 5 && (i / 8) == 3) ||
                ((i % 8) == 3 && (i / 8) == 6)
            )
                memory[128 + i] = 8'd31;
            else
                memory[128 + i] = 8'd30;

        end

    end


    /*
     * Endereço:
     *
     * tile_index * 64
     * +
     * pixel_y * 8
     * +
     * pixel_x
     */
    wire [13:0] address;

    assign address =
        (tile_index * 14'd64) +
        (pixel_y * 3'd8) +
        pixel_x;


    /*
     * Leitura da memória.
     */
    always @(*) begin

        color_index = memory[address];

    end

endmodule