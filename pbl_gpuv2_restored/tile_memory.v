module tile_memory (

    input  wire [7:0] tile_index,
    input  wire [2:0] pixel_x,
    input  wire [2:0] pixel_y,

    output wire [7:0] color_index

);

    /*
     * 256 tiles possíveis.
     *
     * 256 * 8 * 8 = 16384 pixels
     *
     * Cada posição contém um índice
     * de 8 bits para a paleta.
     */
    reg [7:0] memory [0:16383];


    /*
     * Carrega os pixels gerados
     * pelo script Python.
     */
    initial begin
        $readmemh("tiles.hex", memory);
    end


    /*
     * Cada tile ocupa 64 posições:
     *
     * endereço =
     *
     * tile_id * 64
     * +
     * pixel_y * 8
     * +
     * pixel_x
     */
    wire [13:0] address;

    assign address =
        {tile_index, 6'b000000}
        +
        {pixel_y, 3'b000}
        +
        pixel_x;


    /*
     * Leitura do pixel.
     */
    assign color_index = memory[address];


endmodule