//Legal Notice: (C)2021 Altera Corporation. All rights reserved.  Your
//use of Altera Corporation's design tools, logic functions and other
//software and tools, and its AMPP partner logic functions, and any
//output files any of the foregoing (including device programming or
//simulation files), and any associated documentation or information are
//expressly subject to the terms and conditions of the Altera Program
//License Subscription Agreement or other applicable license agreement,
//including, without limitation, that your use is for the sole purpose
//of programming logic devices manufactured by Altera and sold by Altera
//or its authorized distributors.  Please refer to the applicable
//agreement for further details.

// synthesis translate_off
`timescale 1ns / 1ps
// synthesis translate_on

// turn off superfluous verilog processor warnings 
// altera message_level Level1 
// altera message_off 10034 10035 10036 10037 10230 10240 10030 

module soc_system_onchip_memory2_0 (
                                      gpu_address, gpu_write, gpu_writedata, gpu_readdata,
                                     // inputs:
                                      address,
                                      byteenable,
                                      chipselect,
                                      clk,
                                      clken,
                                      freeze,
                                      reset,
                                      reset_req,
                                      write,
                                      writedata,

                                     // outputs:
                                      readdata
                                   )
;

  parameter INIT_FILE = "soc_system_onchip_memory2_0.hex";

  // Integration overlay: same 64-KiB RAM, second physical 64-bit port.
  // Native client sees 32-bit words. Byte enables preserve the other half.
  input [13:0] gpu_address;
  input gpu_write;
  input [31:0] gpu_writedata;
  output [31:0] gpu_readdata;
  wire [63:0] gpu_q;
  reg gpu_lane;


  output  [ 63: 0] readdata;
  input   [ 12: 0] address;
  input   [  7: 0] byteenable;
  input            chipselect;
  input            clk;
  input            clken;
  input            freeze;
  input            reset;
  input            reset_req;
  input            write;
  input   [ 63: 0] writedata;


wire             clocken0;
wire    [ 63: 0] readdata;
wire             wren;
  always @(posedge clk) gpu_lane <= gpu_address[0];
  assign gpu_readdata = gpu_lane ? gpu_q[63:32] : gpu_q[31:0];
  assign wren = chipselect & write;
  assign clocken0 = clken & ~reset_req;
  altsyncram the_altsyncram
    (
      .address_a (address),
      .byteena_a (byteenable),
      .clock0 (clk),
      .clocken0 (clocken0),
      .data_a (writedata),
      .q_a (readdata),
      .aclr0(1'b0), .aclr1(1'b0), .addressstall_a(1'b0), .addressstall_b(1'b0),
      .clocken2(1'b1), .clocken3(1'b1), .rden_a(1'b1), .rden_b(1'b1),
      .wren_a (wren)
      ,.address_b(gpu_address[13:1]), .clock1(clk), .clocken1(1'b1)
      ,.data_b({gpu_writedata,gpu_writedata}), .q_b(gpu_q)
      ,.byteena_b(gpu_address[0] ? 8'hf0 : 8'h0f)
      ,.wren_b(gpu_write & ~reset & ~reset_req)
    );

  defparam the_altsyncram.byte_size = 8,
           the_altsyncram.intended_device_family = "Cyclone V",
           the_altsyncram.init_file = INIT_FILE,
           the_altsyncram.lpm_type = "altsyncram",
           the_altsyncram.maximum_depth = 8192,
           the_altsyncram.numwords_a = 8192,
           the_altsyncram.operation_mode = "BIDIR_DUAL_PORT",
           the_altsyncram.numwords_b = 8192,
           the_altsyncram.width_b = 64,
           the_altsyncram.widthad_b = 13,
           the_altsyncram.width_byteena_b = 8,
           the_altsyncram.address_reg_b = "CLOCK1",
           the_altsyncram.indata_reg_b = "CLOCK1",
           the_altsyncram.byteena_reg_b = "CLOCK1",
           the_altsyncram.wrcontrol_wraddress_reg_b = "CLOCK1",
           the_altsyncram.outdata_reg_b = "UNREGISTERED",
           the_altsyncram.read_during_write_mode_port_b = "DONT_CARE",
           the_altsyncram.outdata_reg_a = "UNREGISTERED",
           the_altsyncram.ram_block_type = "AUTO",
           the_altsyncram.read_during_write_mode_mixed_ports = "DONT_CARE",
           the_altsyncram.read_during_write_mode_port_a = "DONT_CARE",
           the_altsyncram.width_a = 64,
           the_altsyncram.width_byteena_a = 8,
           the_altsyncram.widthad_a = 13;

  //s1, which is an e_avalon_slave
  //s2, which is an e_avalon_slave

endmodule

