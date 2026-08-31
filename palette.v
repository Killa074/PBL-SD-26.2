module palette (

    input  wire [7:0] color_index,

    output reg  [7:0] red,
    output reg  [7:0] green,
    output reg  [7:0] blue

);

    reg [23:0] palette [0:255];

    integer i;

    initial begin

        // Inicializa tudo em preto
        for (i = 0; i < 256; i = i + 1) begin
            palette[i] = 24'h000000;
        end


        // Cores de demonstração

			palette[10] = 24'h1565C0;  // azul água
			palette[11] = 24'h42A5F5;  // azul claro
			palette[20] = 24'h388E3C;  // verde grama
			palette[21] = 24'h66BB6A;  // verde claro
			palette[30] = 24'h8D6E63;  // terra
			palette[31] = 24'hBCAAA4;  // terra clara

    end


    always @(*) begin

        red   = palette[color_index][23:16];

        green = palette[color_index][15:8];

        blue  = palette[color_index][7:0];

    end

endmodule