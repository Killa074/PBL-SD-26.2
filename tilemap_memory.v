module tilemap_memory (

    input  wire        clk,

    // Leitura
    input  wire [10:0] read_address,
    output reg  [7:0]  tile_index,

    // Escrita futura
    input  wire        write_enable,
    input  wire [10:0] write_address,
    input  wire [7:0]  write_data

);

    /*
     * Tilemap:
     *
     * 40 colunas
     * 30 linhas
     *
     * Total = 1200 posições
     */
    reg [7:0] memory [0:1199];

    integer x;
    integer y;
    integer address;


    initial begin

        /*
         * Primeiro:
         * preenche o mapa inteiro com GRAMA.
         *
         * Tile 1 = grama
         */
        for (address = 0; address < 1200; address = address + 1) begin
            memory[address] = 8'd1;
        end


        /*
         * Agora criamos o mapa.
         */
        for (y = 0; y < 30; y = y + 1) begin

            for (x = 0; x < 40; x = x + 1) begin

                address = y * 40 + x;


                /*
                 * ÁGUA NAS BORDAS
                 *
                 * Tile 0 = água
                 */
                if (
                    x < 3 ||
                    x > 36 ||
                    y < 2 ||
                    y > 27
                ) begin

                    memory[address] = 8'd0;

                end


                /*
                 * RIO VERTICAL
                 */
                else if (
                    (x >= 18 && x <= 21) &&
                    !(y >= 13 && y <= 16)
                ) begin

                    memory[address] = 8'd0;

                end


                /*
                 * LAGO
                 */
                else if (
                    x >= 6 &&
                    x <= 12 &&
                    y >= 18 &&
                    y <= 23
                ) begin

                    memory[address] = 8'd0;

                end


                /*
                 * CAMINHO HORIZONTAL
                 *
                 * Tile 2 = terra
                 */
                else if (
                    y >= 8 &&
                    y <= 10 &&
                    x >= 3 &&
                    x <= 36
                ) begin

                    memory[address] = 8'd2;

                end


                /*
                 * CAMINHO VERTICAL
                 */
                else if (
                    x >= 27 &&
                    x <= 29 &&
                    y >= 8 &&
                    y <= 26
                ) begin

                    memory[address] = 8'd2;

                end


                /*
                 * CAMINHO PARA O LAGO
                 */
                else if (
                    y >= 20 &&
                    y <= 22 &&
                    x >= 12 &&
                    x <= 27
                ) begin

                    memory[address] = 8'd2;

                end

            end

        end

    end


    /*
     * Escrita futura.
     */
    always @(posedge clk) begin

        if (write_enable) begin

            if (write_address < 1200)
                memory[write_address] <= write_data;

        end

    end


    /*
     * Leitura do tilemap.
     */
    always @(*) begin

        if (read_address < 1200)
            tile_index = memory[read_address];

        else
            tile_index = 8'd0;

    end

endmodule