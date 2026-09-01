module tilemap_memory (

    input  wire        clk,

    input  wire [10:0] read_address,
    output wire [7:0]  tile_index,

    input  wire        write_enable,
    input  wire [10:0] write_address,
    input  wire [7:0]  write_data

);

    /*
     * 40 x 30 = 1200 posições.
     *
     * Cada posição contém o ID
     * de um tile.
     */
    reg [7:0] memory [0:1199];


    /*
     * Carrega o mapa criado
     * pelo script Python.
     */
    initial begin
        $readmemh("tilemap.hex", memory);
    end


    /*
     * Escrita.
     *
     * Isso será importante depois para
     * alterar o tilemap em execução.
     */
    always @(posedge clk) begin

        if (write_enable) begin

            if (write_address < 11'd1200)
                memory[write_address] <= write_data;

        end

    end


    /*
     * Leitura.
     */
    assign tile_index =
        (read_address < 11'd1200)
        ? memory[read_address]
        : 8'd0;


endmodule