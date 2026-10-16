// Active-fetch 32-bit GPU ISA. One clock domain; OUT uses valid/ready.
module gpu_cpu #(
    parameter PROGRAM_FILE = "programs/demo.hex",
    parameter IMEM_WORDS = 1024
) (
    input wire clk, reset_n, run, restart,
    input wire host_we,
    input wire [9:0] host_addr,
    input wire [31:0] host_data,
    input wire gfx_ready,
    output wire gfx_valid,
    output reg [7:0] gfx_port,
    output reg [31:0] gfx_data,
    output wire busy,
    output reg done, error,
    output reg [9:0] pc,
    output reg [31:0] ir,
    output reg [3:0] flags
);
    localparam IDLE=3'd0, FETCH=3'd1, CAPTURE=3'd2, EXECUTE=3'd3, OUTPUT_WAIT=3'd4;
    reg [2:0] state;
    reg halted;
    reg [31:0] imem [0:IMEM_WORDS-1];
    reg [31:0] registers [0:15];
    reg [31:0] fetched;
    integer i;
    initial begin
        for (i=0; i<IMEM_WORDS; i=i+1) imem[i]=32'hF0000000;
        if (PROGRAM_FILE != "") $readmemh(PROGRAM_FILE,imem);
    end
    // Synchronous RAM with registered read. Configuration preload is not reset.
    always @(posedge clk) begin
        if (host_we && !run && state != OUTPUT_WAIT && host_addr < IMEM_WORDS)
            imem[host_addr] <= host_data;
        if (reset_n && !restart && run && state == FETCH && pc < IMEM_WORDS)
            fetched <= imem[pc];
    end
    wire [3:0] op=ir[31:28], rd=ir[27:24], ra=ir[23:20], rb=ir[19:16];
    wire [31:0] a=(ra==0)?32'd0:registers[ra];
    wire [31:0] b=(rb==0)?32'd0:registers[rb];
    reg [31:0] result;
    reg [32:0] wide;
    reg carry, overflow, legal;
    wire alu_op=(op>=4'h2 && op<=4'h8) || op==4'hD;
    wire branch=(op==4'hB) || (op==4'hC && a==0);
    // All unspecified instruction bits must be zero: malformed commands fault.
    always @* begin
        result=0; wide=0; carry=0; overflow=0; legal=1;
        case (op)
            4'h0: legal=(ir[27:0]==0);
            4'h1: begin result={{16{ir[15]}},ir[15:0]}; legal=(ir[23:16]==0); end
            4'h2: begin wide={1'b0,a}+{1'b0,b}; result=wide[31:0]; carry=wide[32]; overflow=(a[31]==b[31])&&(result[31]!=a[31]); legal=(ir[15:0]==0); end
            4'h3: begin wide={1'b0,a}+{1'b0,~b}+33'd1; result=wide[31:0]; carry=wide[32]; overflow=(a[31]!=b[31])&&(result[31]!=a[31]); legal=(ir[15:0]==0); end
            4'h4: begin result=a&b; legal=(ir[15:0]==0); end
            4'h5: begin result=a|b; legal=(ir[15:0]==0); end
            4'h6: begin result=a^b; legal=(ir[15:0]==0); end
            4'h7: begin result=a<<b[4:0]; if(b[4:0]!=0) carry=a[32-b[4:0]]; legal=(ir[15:0]==0); end
            4'h8: begin result=a>>b[4:0]; if(b[4:0]!=0) carry=a[b[4:0]-1]; legal=(ir[15:0]==0); end
            4'h9: begin result=a; legal=(ir[19:0]==0); end
            4'hA: legal=(ir[27:24]==0 && ir[19:8]==0);
            4'hB: legal=(ir[27:10]==0);
            4'hC: legal=(ir[27:24]==0 && ir[19:10]==0);
            4'hD: begin result=($signed(a)<$signed(b))?32'd1:32'd0; legal=(ir[15:0]==0); end
            4'hE: begin result={ir[15:0],16'd0}; legal=(ir[23:16]==0); end
            4'hF: legal=(ir[27:0]==0);
            default: legal=0;
        endcase
    end
    // Once OUT is offered, pausing run cannot withdraw it. It retires once.
    assign gfx_valid=(state==OUTPUT_WAIT) && !restart && reset_n;
    assign busy=!halted && (run || state==OUTPUT_WAIT);
    integer r;
    always @(posedge clk) begin
        if (!reset_n || restart) begin
            state<=IDLE; halted<=0; done<=0; error<=0;
            pc<=0; ir<=0; flags<=0; gfx_port<=0; gfx_data<=0;
            for(r=0;r<16;r=r+1) registers[r]<=0;
        end else if (!halted) begin
            if (state==OUTPUT_WAIT) begin
                if (gfx_ready) begin
                    if (pc==IMEM_WORDS-1) begin error<=1; halted<=1; state<=IDLE; end
                    else begin pc<=pc+10'd1; state<=FETCH; end
                end
            end else if (run) begin
                case(state)
                    IDLE: state<=FETCH;
                    FETCH: begin
                        if(pc>=IMEM_WORDS) begin error<=1; halted<=1; state<=IDLE; end
                        else state<=CAPTURE;
                    end
                    CAPTURE: begin ir<=fetched; state<=EXECUTE; end
                    EXECUTE: begin
                        if(!legal) begin error<=1; halted<=1; state<=IDLE; end
                        else if(op==4'hF) begin done<=1; halted<=1; state<=IDLE; end
                        else if(op==4'hA) begin gfx_port<=ir[7:0]; gfx_data<=a; state<=OUTPUT_WAIT; end
                        else if(branch) begin
                            if(ir[9:0]>=IMEM_WORDS) begin error<=1; halted<=1; state<=IDLE; end
                            else begin pc<=ir[9:0]; state<=FETCH; end
                        end else begin
                            if(op==4'h1 || op==4'h9 || op==4'hE || alu_op)
                                if(rd!=0) registers[rd]<=result;
                            if(alu_op) flags<={overflow,carry,result[31],result==0};
                            if(pc==IMEM_WORDS-1) begin error<=1; halted<=1; state<=IDLE; end
                            else begin pc<=pc+10'd1; state<=FETCH; end
                        end
                    end
                    default: begin error<=1; halted<=1; state<=IDLE; end
                endcase
            end
        end
    end
endmodule
