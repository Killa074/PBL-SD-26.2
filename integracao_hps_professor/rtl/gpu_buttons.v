// Asynchronous assertion, synchronous reset release, and a debounced KEY1.
module gpu_buttons (
    input wire clk, input wire reset_button_n, input wire start_button_n,
    output wire reset_n, output reg start_pulse
);
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [1:0] reset_pipe;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [1:0] start_pipe;
    reg [18:0] debounce;
    reg armed;
    always @(posedge clk or negedge reset_button_n)
        if (!reset_button_n) reset_pipe <= 2'b00;
        else reset_pipe <= {reset_pipe[0], 1'b1};
    assign reset_n = reset_pipe[1];
    always @(posedge clk) begin
        if (!reset_n) begin
            start_pipe <= 2'b11;
            debounce <= 0;
            start_pulse <= 0;
            armed <= 1;
        end else begin
            start_pipe <= {start_pipe[0], start_button_n};
            start_pulse <= 0;
            if (start_pipe[1]) begin
                debounce <= 0;
                armed <= 1;
            end else if (armed) begin
                if (debounce == 19'd499999) begin
                    start_pulse <= 1;
                    armed <= 0;
                end else debounce <= debounce + 1'b1;
            end
        end
    end
endmodule
