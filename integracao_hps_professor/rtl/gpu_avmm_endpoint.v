// One-cycle response for the Platform Designer exported Avalon-MM master.
// gpu_host itself reads combinationally and never asserts waitrequest.
module gpu_avmm_endpoint (
    input wire clk, reset_n,
    input wire [5:0] bus_address,
    input wire bus_read, bus_write,
    input wire [3:0] bus_byteenable,
    output wire bus_waitrequest,
    output reg [31:0] bus_readdata,
    output reg bus_readdatavalid,
    output wire [5:0] core_address,
    output wire core_read, core_write,
    input wire [31:0] core_readdata
);
    assign bus_waitrequest = !reset_n;
    // Route unsupported partial writes to a reserved address. The host
    // latches ERROR[0] and cannot corrupt a live command/register.
    assign core_address = bus_write && bus_byteenable != 4'hf ? 6'h3f : bus_address;
    assign core_read = reset_n && bus_read;
    assign core_write = reset_n && bus_write;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            bus_readdatavalid <= 0;
            bus_readdata <= 0;
        end else begin
            bus_readdatavalid <= bus_read;
            if (bus_read) bus_readdata <= core_readdata;
        end
    end
endmodule
