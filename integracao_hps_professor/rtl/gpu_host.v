// Register MMIO slave plus a 64-command passive queue. Addresses are WORDS.
module gpu_host #(
    parameter PROGRAM_FILE="programs/demo.hex",
    parameter IMEM_WORDS=1024
) (
    input wire clk,reset_n,
    input wire [5:0] avs_address,
    input wire avs_read,avs_write,
    input wire [31:0] avs_writedata,
    output reg [31:0] avs_readdata,
    output wire avs_waitrequest,
    input wire demo_start,
    output wire gfx_valid,
    output wire [7:0] gfx_port,
    output wire [31:0] gfx_data,
    input wire gfx_ready,gfx_busy,gfx_done,gfx_error,
    input wire [31:0] gfx_frame_count
);
    reg run_reg,passive,cpu_restart,cpu_we,passive_pending;
    reg [9:0] cpu_write_addr;
    reg [31:0] cpu_write_data,imem_address;
    wire cpu_valid,cpu_busy,cpu_done,cpu_error;
    wire [7:0] cpu_port;
    wire [31:0] cpu_data,cpu_ir;
    wire [9:0] cpu_pc;
    wire [3:0] cpu_flags;
    gpu_cpu #(.PROGRAM_FILE(PROGRAM_FILE),.IMEM_WORDS(IMEM_WORDS)) cpu (
        .clk(clk),.reset_n(reset_n),.run(run_reg && !passive),.restart(cpu_restart),
        .host_we(cpu_we),.host_addr(cpu_write_addr),.host_data(cpu_write_data),
        .gfx_ready(gfx_ready && !passive),.gfx_valid(cpu_valid),
        .gfx_port(cpu_port),.gfx_data(cpu_data),.busy(cpu_busy),.done(cpu_done),
        .error(cpu_error),.pc(cpu_pc),.ir(cpu_ir),.flags(cpu_flags)
    );
    reg [39:0] fifo[0:63];
    reg [5:0] wr_pointer,rd_pointer;
    reg [6:0] fifo_count;
    reg [7:0] staged_port,last_port;
    reg [31:0] last_data,out_count;
    reg [6:0] errors;
    assign avs_waitrequest=1'b0;
    assign gfx_valid=reset_n && !cpu_restart && (passive ? passive_pending : cpu_valid);
    assign gfx_port=passive ? fifo[rd_pointer][39:32] : cpu_port;
    assign gfx_data=passive ? fifo[rd_pointer][31:0] : cpu_data;
    wire accepted=gfx_valid && gfx_ready;
    wire pop=accepted && passive;
    wire push=avs_write && avs_address==6'h0D && passive && (fifo_count<64 || pop);
    wire mode_change=(avs_writedata[2]!=passive);
    wire control_ok=(!mode_change || (!cpu_busy && !gfx_busy && fifo_count==0)) &&
                    (!avs_writedata[1] || !gfx_busy);
    wire restart_write=avs_write && avs_address==6'h01 && control_ok && avs_writedata[1];
    wire key_restart=demo_start && !cpu_busy && !gfx_busy && fifo_count==0;
    wire address_known=(avs_address<=6'h0A) || (avs_address>=6'h0C && avs_address<=6'h10);
    always @* begin
        avs_readdata=0;
        case(avs_address)
            6'h00: avs_readdata=32'h47505533; // GPU3 interface version
            6'h01: avs_readdata={29'd0,passive,1'b0,run_reg};
            6'h02: begin
                avs_readdata[0]=cpu_busy; avs_readdata[1]=cpu_done;
                avs_readdata[2]=(|errors)||cpu_error||gfx_error;
                avs_readdata[3]=gfx_busy; avs_readdata[4]=(fifo_count==0);
                avs_readdata[5]=(fifo_count==64); avs_readdata[6]=passive;
                avs_readdata[7]=gfx_done; avs_readdata[8]=run_reg;
                avs_readdata[9]=cpu_error;
            end
            6'h03: avs_readdata=imem_address;
            6'h04: avs_readdata=0; // IMEM_DATA is write only
            6'h05: avs_readdata={22'd0,cpu_pc};
            6'h06: avs_readdata=cpu_ir;
            6'h07: avs_readdata=last_data;
            6'h08: avs_readdata={24'd0,last_port};
            6'h09: avs_readdata=out_count;
            6'h0A: avs_readdata={28'd0,cpu_flags};
            6'h0C: avs_readdata={24'd0,staged_port};
            6'h0D: avs_readdata=0; // CMD_DATA is write only
            6'h0E: avs_readdata=32'd64-{25'd0,fifo_count};
            6'h0F: avs_readdata=gfx_frame_count;
            6'h10: avs_readdata={25'd0,errors} | (cpu_error?32'h10:0) | (gfx_error?32'h20:0);
            default: avs_readdata=0;
        endcase
    end
    always @(posedge clk) begin
        if(!reset_n) begin
            run_reg<=0; passive<=0; cpu_restart<=0; cpu_we<=0; passive_pending<=0;
            cpu_write_addr<=0; cpu_write_data<=0; imem_address<=0;
            wr_pointer<=0; rd_pointer<=0; fifo_count<=0; staged_port<=0;
            last_port<=0; last_data<=0; out_count<=0; errors<=0;
        end else begin
            cpu_restart<=0; cpu_we<=0;
            if(accepted && passive) passive_pending<=0;
            else if(passive && run_reg && fifo_count!=0) passive_pending<=1;
            if(cpu_error) errors[4]<=1;
            if(gfx_error) errors[5]<=1;
            if(avs_read && !address_known) errors[0]<=1;
            if(accepted) begin last_port<=gfx_port; last_data<=gfx_data; out_count<=out_count+1; end
            if(pop) rd_pointer<=rd_pointer+1'b1;
            if(push) begin fifo[wr_pointer]<={staged_port,avs_writedata}; wr_pointer<=wr_pointer+1'b1; end
            case({push,pop})
                2'b10: fifo_count<=fifo_count+1'b1;
                2'b01: fifo_count<=fifo_count-1'b1;
                default: ;
            endcase
            if(avs_write) begin
                case(avs_address)
                    6'h01: begin
                        if(control_ok) begin
                            run_reg<=avs_writedata[0]; passive<=avs_writedata[2];
                            if(avs_writedata[3]) errors<=0;
                        end else errors[3]<=1;
                    end
                    6'h03: imem_address<=avs_writedata;
                    6'h04: begin
                        if(!run_reg && !cpu_busy && imem_address<IMEM_WORDS) begin
                            cpu_we<=1; cpu_write_addr<=imem_address[9:0]; cpu_write_data<=avs_writedata;
                            imem_address<=imem_address+1'b1;
                        end else errors[1]<=1;
                    end
                    6'h0C: begin
                        if(avs_writedata[31:8]==0) staged_port<=avs_writedata[7:0];
                        else errors[0]<=1;
                    end
                    6'h0D: begin
                        if(!passive) errors[6]<=1;
                        else if(!push) errors[2]<=1;
                    end
                    6'h10: errors<=errors & ~avs_writedata[6:0];
                    default: errors[0]<=1;
                endcase
            end
            if(restart_write || key_restart) begin
                cpu_restart<=1;
                passive_pending<=0;
                wr_pointer<=0; rd_pointer<=0; fifo_count<=0;
                last_port<=0; last_data<=0; out_count<=0;
                if(key_restart) begin run_reg<=1; passive<=0; end
            end
        end
    end
endmodule
