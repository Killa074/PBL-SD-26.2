module background_engine (

    input  wire        clk,

    input  wire [8:0]  logical_x,
    input  wire [7:0]  logical_y,

    // Futuro controle de scroll
    input  wire [8:0]  scroll_x,
    input  wire [7:0]  scroll_y,

    output wire [7:0]  color_index

);

    /*
     * Coordenadas após scroll.
     *
     * Estamos usando wrap-around.
     */

    wire [8:0] world_x;
    wire [7:0] world_y;

    assign world_x = logical_x + scroll_x;
    assign world_y = logical_y + scroll_y;


    /*
     * Qual tile estamos acessando?
     */

    wire [5:0] tile_x;
    wire [4:0] tile_y;

    assign tile_x = world_x[8:3];
    assign tile_y = world_y[7:3];


    /*
     * Pixel dentro do tile 8x8
     */

    wire [2:0] pixel_in_tile_x;
    wire [2:0] pixel_in_tile_y;

    assign pixel_in_tile_x = world_x[2:0];
    assign pixel_in_tile_y = world_y[2:0];


    /*
     * Endereço do tilemap.
     *
     * tile_y * 40 + tile_x
     */

    wire [10:0] tilemap_address;

    assign tilemap_address =
        tile_y * 6'd40 +
        tile_x;


    /*
     * Índice do tile
     */

    wire [7:0] tile_index;


    tilemap_memory tilemap (

        .clk           (clk),

        .read_address  (tilemap_address),
        .tile_index    (tile_index),

        // Ainda sem interface externa
        .write_enable  (1'b0),
        .write_address (11'd0),
        .write_data    (8'd0)

    );


    /*
     * Busca pixel dentro do tile
     */

    tile_memory tiles (

        .tile_index (tile_index),

        .pixel_x    (pixel_in_tile_x),
        .pixel_y    (pixel_in_tile_y),

        .color_index(color_index)

    );

endmodule