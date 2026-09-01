module background_engine (

    input  wire        clk,

    input  wire [8:0]  logical_x,
    input  wire [7:0]  logical_y,

    /*
     * Interface de escrita do tilemap.
     */
    input  wire        tilemap_write_enable,
    input  wire [10:0] tilemap_write_address,
    input  wire [7:0]  tilemap_write_data,

    output wire [7:0]  color_index

);


    /*
     * =====================================================
     * POSIÇÃO NO TILEMAP
     * =====================================================
     *
     * Cada tile possui 8x8 pixels.
     */

    wire [5:0] tile_x;
    wire [4:0] tile_y;

    assign tile_x = logical_x[8:3];
    assign tile_y = logical_y[7:3];


    /*
     * =====================================================
     * PIXEL DENTRO DO TILE
     * =====================================================
     */

    wire [2:0] pixel_in_tile_x;
    wire [2:0] pixel_in_tile_y;

    assign pixel_in_tile_x = logical_x[2:0];
    assign pixel_in_tile_y = logical_y[2:0];


    /*
     * =====================================================
     * ENDEREÇO DO TILEMAP
     * =====================================================
     *
     * address = y * 40 + x
     */

    wire [10:0] tile_y_extended;
    wire [10:0] tile_x_extended;

    assign tile_y_extended = {6'd0, tile_y};
    assign tile_x_extended = {5'd0, tile_x};


    wire [10:0] tilemap_address;

    /*
     * y * 40
     *
     * 40 = 32 + 8
     *
     * então:
     *
     * y*40 = y*32 + y*8
     */
    assign tilemap_address =
        (tile_y_extended << 5) +
        (tile_y_extended << 3) +
        tile_x_extended;


    /*
     * =====================================================
     * TILEMAP
     * =====================================================
     */

    wire [7:0] tile_index;


    tilemap_memory tilemap (

        .clk           (clk),

        .read_address  (tilemap_address),
        .tile_index    (tile_index),

        .write_enable  (tilemap_write_enable),
        .write_address (tilemap_write_address),
        .write_data    (tilemap_write_data)

    );


    /*
     * =====================================================
     * MEMÓRIA DOS TILES
     * =====================================================
     */

    tile_memory tiles (

        .tile_index  (tile_index),

        .pixel_x     (pixel_in_tile_x),
        .pixel_y     (pixel_in_tile_y),

        .color_index (color_index)

    );


endmodule