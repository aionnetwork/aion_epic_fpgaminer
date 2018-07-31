/* © Copyright ePIC Blockchain Technologies Inc. (2018).  All Rights Reserved.
 * Written by emai <emai@epicblockchain.io> June 2018
 */
`include "equihash_defines.v"

module mem_gasket (
  input                           eclk,
  input                           rstb,

  input  [2:0]                    state,

  input                           memc_cmd_full,
  output                          memc_cmd_en,
  output [2:0]                    memc_cmd_instr,
  output [5:0]                    memc_cmd_bl,
  output [27:0]                   memc_cmd_addr,

  output                          memc_wr_en,
  output                          memc_wr_end,

  output [63:0]                   memc_wr_mask,
  output [511:0]                  memc_wr_data,
  input                           memc_wr_full,

  output                          memc_rd_en,
  input [511:0]                   memc_rd_data,
  input                           memc_rd_empty,

  /* Write Memory ports (3)
  wire [`MEM_DATA_WIDTH-1:0] wbdata, wcdata, wrdata, wsdata;
  wire                       wbvalid, wcvalid, wrvalid, wsvalid;

  // Read Memory ports (2)
  wire [`MEM_ADDR_WIDTH-1:0] rcaddr, rraddr;
  wire                       rcsend, rrsend;
  wire [`MEM_DATA_WIDTH-1:0] rcdata, rrdata;
  wire                       rcvalid, rrvalid;*/

  input [`MEM_ADDR_WIDTH-1:0]    wbaddr,
  input [`MEM_DATA_WIDTH-1:0]    wbdata,
  input                          wbvalid,

  input [`MEM_ADDR_WIDTH-1:0]    wcaddr,
  input [`MEM_DATA_WIDTH-1:0]    wcdata,
  input                          wcvalid,


  input [`MEM_ADDR_WIDTH-1:0]    wraddr,
  input [`MEM_DATA_WIDTH-1:0]    wrdata,
  input                          wrvalid,

  input                          rcsend,
  input [`MEM_ADDR_WIDTH-1:0]    rcaddr,

  input                          rrsend,
  input [`MEM_ADDR_WIDTH-1:0]    rraddr,

  output [`MEM_DATA_WIDTH-1:0]   rcdata,
  output                         rcvalid,

  output [`MEM_DATA_WIDTH-1:0]   rrdata,
  output                         rrvalid

  );

  /*
  localparam STATE_BLAKE2B   = 3'h1;
  localparam STATE_RADIX     = 3'h2;
  localparam STATE_COLLISION = 3'h3;
  */

  wire [2:0] memc_cmd_instr;
  wire       memc_cmd_en;
  wire [5:0] memc_cmd_bl;
  wire memc_wr_en,memc_wr_end;
  wire memc_rd_en;
  wire [`MEM_DATA_WIDTH-1:0]   rcdata, rrdata;
  wire rcvalid, rrvalid;
  wire [63:0] memc_wr_mask;


  reg wbvalidq, wrvalidq, wcvalidq;
  reg [27:0] wbaddrq, wraddrq, wcaddrq;

  reg rrsendq, rcsendq;
  reg [27:0] rraddrq, rcaddrq;
  always @(posedge eclk)
  begin
    if (!rstb)
    begin
      wbvalidq <= 1'b0;
      wrvalidq <= 1'b0;
      wcvalidq <= 1'b0;
      wbaddrq  <= 28'h0;
      wraddrq  <= 28'h0;
      wcaddrq  <= 28'h0;

      rrsendq  <= 1'b0;
      rcsendq  <= 1'b0;
      rraddrq  <= 28'h0;
      rcaddrq  <= 28'h0;
    end
    else
    begin
      wbvalidq <= wbvalid;
      wrvalidq <= wrvalid;
      wcvalidq <= wcvalid;
      wbaddrq  <= wbaddr[27:0];
      wraddrq  <= wraddr[27:0];
      wcaddrq  <= wcaddr[27:0];

      rrsendq  <= rrsend;
      rcsendq  <= rcsend;
      rraddrq  <= rraddr;
      rcaddrq  <= rcaddr;
    end
  end

  assign rcdata =  (state==3'h3) ? memc_rd_data[255:0] : 256'h0;
  assign rrdata =  (state==3'h2) ? memc_rd_data[255:0] : 256'h0;
  assign rcvalid = (state==3'h3) ? !memc_rd_empty : 1'b0;
  assign rrvalid = (state==3'h2) ? !memc_rd_empty : 1'b0;

  assign memc_cmd_instr = (rcsend||rrsend) ? 3'b1 : 3'b0;
  assign memc_cmd_en =(wbvalid||wrvalid||wcvalid||rcsend||rrsend);
  assign memc_cmd_bl = 6'h1;
  assign memc_wr_en  = (wbvalid||wrvalid||wcvalid);
  assign memc_wr_end = 1'b1;
  assign memc_rd_en  = (rrsend||rcsend);
  assign memc_wr_mask = {64'h0};


  reg [27:0]                   memc_cmd_addr;
  reg [511:0]                  memc_wr_data;

  always @(*)
  begin
    if (wbvalid||wrvalid||wcvalid)
      case(state)
        3'h1    : begin memc_cmd_addr = {wbaddr[28:0],3'b0};  memc_wr_data = {256'h0,wbdata}; end
        3'h2    : begin memc_cmd_addr = {wraddr[28:0],3'b0};  memc_wr_data = {256'h0,wrdata}; end
        3'h3    : begin memc_cmd_addr = {wcaddr[28:0],3'b0};  memc_wr_data = {256'h0,wcdata}; end
        default : begin memc_cmd_addr = 32'h0;  memc_wr_data = 512'h0; end
      endcase
    else if (rrsend||rcsend)
      case(state)
        3'h2    : begin memc_cmd_addr = {rraddr[28:0],3'b0}; memc_wr_data = 512'h0; end
        3'h3    : begin memc_cmd_addr = {rcaddr[28:0],3'b0}; memc_wr_data = 512'h0;end
        default : begin memc_cmd_addr = 32'h0;   memc_wr_data = 512'h0; end
      endcase
    else
    begin
      memc_cmd_addr = 32'h0;
      memc_wr_data = 512'h0;
    end
  end

endmodule //mem_gasket
