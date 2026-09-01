module palette (

    input  wire [7:0] color_index,

    output wire [7:0] red,
    output wire [7:0] green,
    output wire [7:0] blue

);

    /*
     * Paleta:
     *
     * 256 cores
     * cada cor = 24 bits
     *
     * RRRRRRRR GGGGGGGG BBBBBBBB
     */
    reg [23:0] memory [0:255];


    /*
     * Carrega a paleta gerada
     * pelo script Python.
     */
    initial begin
        $readmemh("palette.hex", memory);
    end


    /*
     * Cor correspondente ao índice.
     */
    wire [23:0] rgb;

    assign rgb = memory[color_index];


    assign red   = rgb[23:16];
    assign green = rgb[15:8];
    assign blue  = rgb[7:0];


endmodule