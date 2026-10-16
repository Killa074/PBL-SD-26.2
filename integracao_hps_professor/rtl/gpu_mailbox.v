// Shared RAM ABI v1. RAM port is synchronous (one cycle), WORD addresses.
// Only this module owns GPU3: no button/JTAG producer may interleave writes.
module gpu_mailbox #(parameter FIFO_TIMEOUT=50000000) (
    input wire clk, reset_n,
    output reg [13:0] mem_address,
    output reg mem_write,
    output wire [31:0] mem_writedata,
    input wire [31:0] mem_readdata,
    output reg [5:0] gpu_address,
    output reg gpu_read, gpu_write,
    output reg [31:0] gpu_writedata,
    input wire [31:0] gpu_readdata,
    output wire busy
);
    localparam BOOT=0, ABI=1, MAGIC=2, POLL=3, POLL_CAPTURE=4,
        CONFIRM=5, CONFIRM_CAPTURE=6, DESC=7, DESC_CAPTURE=8,
        MARK_BUSY=9, DISPATCH=10, REG_READ=11, REG_WRITE=12,
        CHECK_PROGRAM=13, IMEM_ZERO=14, FETCH=15, FETCH_CAPTURE=16,
        IMEM_WRITE=17, FETCH_DATA=18, DATA_CAPTURE=19, FIFO_WAIT=20,
        PORT_WRITE=21, DATA_WRITE=22, NEXT=23, SNAPSHOT=24,
        RESULT_WRITE=25, COUNT_WRITE=26, ERROR_WRITE=27,
        IDLE_WRITE=28, DONE_WRITE=29;
    reg [5:0] state;
    reg [5:0] boot_index;
    reg [2:0] desc_index, snapshot_index;
    reg [31:0] request, last_request, operation, count, arg0, arg1;
    reg [31:0] processed, result, error_code, item, item_data, stall;
    reg [31:0] mem_data_local;
    // Keep the host-read -> RAM-data path separate from address decode.
    // Otherwise combinational read mux glitches can form a simulation delta loop.
    assign mem_writedata = state==SNAPSHOT ? gpu_readdata : mem_data_local;
    assign busy = state>=DESC && state<=DONE_WRITE;
    always @* begin
        mem_address=0; mem_write=0; mem_data_local=0;
        gpu_address=0; gpu_read=0; gpu_write=0; gpu_writedata=0;
        case(state)
            BOOT: begin mem_address={8'd0,boot_index}; mem_write=1; end
            ABI: begin mem_address=1; mem_write=1; mem_data_local=1; end
            MAGIC: begin mem_write=1; mem_data_local=32'h48505347; end // HPSG
            POLL,CONFIRM: mem_address=16; // request has its own 64-bit RAM word
            DESC: mem_address=14'd18+{11'd0,desc_index};
            MARK_BUSY: begin mem_address=4; mem_write=1; mem_data_local=1; end
            REG_READ: begin gpu_read=1; gpu_address=arg0[7:2]; end
            REG_WRITE: begin gpu_write=1; gpu_address=arg0[7:2]; gpu_writedata=arg1; end
            DISPATCH: begin gpu_read=1; gpu_address=1; end // CONTROL
            CHECK_PROGRAM: begin gpu_read=1; gpu_address=2; end // STATUS
            IMEM_ZERO: begin gpu_write=1; gpu_address=3; end
            FETCH: mem_address=14'd64 + (operation==3 ? processed[13:0] : {processed[12:0],1'b0});
            FETCH_DATA: mem_address=14'd65+{processed[12:0],1'b0};
            IMEM_WRITE: begin gpu_write=1; gpu_address=4; gpu_writedata=item; end
            FIFO_WAIT: begin gpu_read=1; gpu_address=14; end
            PORT_WRITE: begin gpu_write=1; gpu_address=12; gpu_writedata=item; end
            DATA_WRITE: begin gpu_write=1; gpu_address=13; gpu_writedata=item_data; end
            SNAPSHOT: begin
                gpu_read=1; mem_write=1;
                case(snapshot_index)
                    0: begin gpu_address=2; mem_address=8; end
                    1: begin gpu_address=16; mem_address=9; end
                    2: begin gpu_address=15; mem_address=10; end
                    3: begin gpu_address=9; mem_address=11; end
                    4: begin gpu_address=5; mem_address=12; end
                    5: begin gpu_address=6; mem_address=13; end
                    default: begin gpu_address=1; mem_address=14; end
                endcase
            end
            RESULT_WRITE: begin mem_address=6; mem_write=1; mem_data_local=result; end
            COUNT_WRITE: begin mem_address=7; mem_write=1; mem_data_local=processed; end
            ERROR_WRITE: begin mem_address=5; mem_write=1; mem_data_local=error_code; end
            IDLE_WRITE: begin mem_address=4; mem_write=1; end
            DONE_WRITE: begin mem_address=2; mem_write=1; mem_data_local=request; end
            default: ;
        endcase
        if(!reset_n) begin mem_write=0; gpu_read=0; gpu_write=0; end
    end
    always @(posedge clk) begin
        if(!reset_n) begin
            state<=BOOT; boot_index<=0; desc_index<=0; snapshot_index<=0;
            request<=0; last_request<=0; operation<=0; count<=0; arg0<=0; arg1<=0;
            processed<=0; result<=0; error_code<=0; item<=0; item_data<=0; stall<=0;
        end else case(state)
            BOOT: if(boot_index==31) state<=ABI; else boot_index<=boot_index+1'b1;
            ABI: state<=MAGIC;
            MAGIC: state<=POLL;
            POLL: state<=POLL_CAPTURE;
            POLL_CAPTURE: begin
                if(mem_readdata!=0 && mem_readdata!=last_request) begin
                    request<=mem_readdata; state<=CONFIRM;
                end else state<=POLL;
            end
            CONFIRM: state<=CONFIRM_CAPTURE;
            CONFIRM_CAPTURE: begin
                // Reject a transient value during a cross-port RAM collision.
                if(mem_readdata==request) begin
                    desc_index<=0; processed<=0; result<=0; error_code<=0;
                    snapshot_index<=0; stall<=0; state<=DESC;
                end else state<=POLL;
            end
            DESC: state<=DESC_CAPTURE;
            DESC_CAPTURE: begin
                case(desc_index)
                    0: operation<=mem_readdata;
                    1: count<=mem_readdata;
                    2: arg0<=mem_readdata;
                    3: arg1<=mem_readdata;
                    default: ;
                endcase
                if(desc_index==3) state<=MARK_BUSY;
                else begin desc_index<=desc_index+1'b1; state<=DESC; end
            end
            MARK_BUSY: state<=DISPATCH;
            DISPATCH: begin
                if(operation==1 || operation==2) begin
                    if(arg0[1:0]!=0 || arg0>32'h40) begin error_code<=2; state<=SNAPSHOT; end
                    else state<=operation==1 ? REG_READ : REG_WRITE;
                end else if(operation==3) begin
                    if(count==0 || count>1024) begin error_code<=2; state<=SNAPSHOT; end
                    else if(gpu_readdata!=0) begin error_code<=3; state<=SNAPSHOT; end
                    else state<=CHECK_PROGRAM;
                end else if(operation==4) begin
                    if(count==0 || count>4096) begin error_code<=2; state<=SNAPSHOT; end
                    else if(gpu_readdata!=5) begin error_code<=3; state<=SNAPSHOT; end
                    else state<=FETCH;
                end else begin error_code<=1; state<=SNAPSHOT; end
            end
            REG_READ: begin result<=gpu_readdata; state<=SNAPSHOT; end
            REG_WRITE: state<=SNAPSHOT;
            CHECK_PROGRAM: begin
                if((gpu_readdata & 32'h19)!=32'h10) begin error_code<=3; state<=SNAPSHOT; end
                else state<=IMEM_ZERO;
            end
            IMEM_ZERO: state<=FETCH;
            FETCH: state<=FETCH_CAPTURE;
            FETCH_CAPTURE: begin
                item<=mem_readdata;
                if(operation==3) state<=IMEM_WRITE;
                else if(mem_readdata>255) begin error_code<=4; state<=SNAPSHOT; end
                else state<=FETCH_DATA;
            end
            IMEM_WRITE: state<=NEXT;
            FETCH_DATA: state<=DATA_CAPTURE;
            DATA_CAPTURE: begin item_data<=mem_readdata; stall<=0; state<=FIFO_WAIT; end
            FIFO_WAIT: begin
                if(gpu_readdata!=0) state<=PORT_WRITE;
                else if(stall>=FIFO_TIMEOUT-1) begin error_code<=5; state<=SNAPSHOT; end
                else stall<=stall+1'b1;
            end
            PORT_WRITE: state<=DATA_WRITE;
            DATA_WRITE: state<=NEXT;
            NEXT: begin
                processed<=processed+1'b1;
                if(processed+1==count) state<=SNAPSHOT; else state<=FETCH;
            end
            SNAPSHOT: if(snapshot_index==6) state<=RESULT_WRITE; else snapshot_index<=snapshot_index+1'b1;
            RESULT_WRITE: state<=COUNT_WRITE;
            COUNT_WRITE: state<=ERROR_WRITE;
            ERROR_WRITE: state<=IDLE_WRITE;
            IDLE_WRITE: state<=DONE_WRITE;
            DONE_WRITE: begin last_request<=request; state<=POLL; end
            default: state<=BOOT;
        endcase
    end
endmodule
