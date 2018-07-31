/* © Copyright ePIC Blockchain Technologies Inc. (2018).  All Rights Reserved.
 * Written by emai <emai@epicblockchain.io> June 2018
 */

/* "collision_store" block reads from the stream_buffer detecting collisions.
 * This block then generates the corresponding writes for XOR data and Pairs
 * data which are subsequently used in the next stage.  In the last stage,
 * collisions are sent to the binary_search FIFO to be traversed. Up to 4
 * collisions are supported and the writes subsequently stall reading from the
 * stream_buffer.  The collision store state machine (cstore_fsm) controls the
 * flow of data.
 */

`include "equihash_defines.v"

module collision_store(
  input             eclk,
  input             rstb,

  input [3:0]       stage,
  input             memc_cmd_full,

  input             collision_start,
  input             collision_stream_done,
  input             stream_empty,
  input             binary_empty,
  input             dcr_empty,
  output            collision_store_done,

  input [`MEM_ADDR_WIDTH-1:0]  stage_pair_base,
  output [`MEM_ADDR_WIDTH-1:0] stage_pair_end,

  input [`MEM_ADDR_WIDTH-1:0]  stage_nxor_base,
  output[`MEM_ADDR_WIDTH-1:0]  stage_nxor_end,
  input [`MEM_ADDR_WIDTH-1:0]  stage_nxor_limit,

  input [`MEM_DATA_WIDTH-1:0]  bdata,
  input                        bvalid,
  output                       bstall,

  output                       bsvalid,
  output [`MEM_ADDR_WIDTH-1:0] bsdata,

  output                       wvalid,
  output                       wvalid_snoop,
  output [`MEM_ADDR_WIDTH-1:0] waddr,
  output [`MEM_DATA_WIDTH-1:0] wdata

);

localparam CSSTATE_IDLE      = 4'h0;
localparam CSSTATE_STALL     = 4'h1;
localparam CSSTATE_PAIR01    = 4'h2;
localparam CSSTATE_XOR01     = 4'h3;
localparam CSSTATE_PAIR02    = 4'h4;
localparam CSSTATE_XOR02     = 4'h5;
localparam CSSTATE_PAIR12    = 4'h6;
localparam CSSTATE_XOR12     = 4'h7;
localparam CSSTATE_PAIR03    = 4'h8;
localparam CSSTATE_XOR03     = 4'h9;
localparam CSSTATE_PAIR13    = 4'hA;
localparam CSSTATE_XOR13     = 4'hB;
localparam CSSTATE_PAIR23    = 4'hC;
localparam CSSTATE_XOR23     = 4'hD;
localparam CSSTATE_UNSTALL   = 4'hE;
localparam CSSTATE_DONE      = 4'hF;

reg [3:0] cstore_state;
reg [3:0] cstore_state_next;
reg       cstore_stall;

reg collision_store_done;
reg collision_store_done_valid;

wire [`MEM_DATA_WIDTH-1:0] wdata;

reg [`MEM_DATA_WIDTH-1:0] wpdata256;
reg [`MEM_DATA_WIDTH-1:0] wpdata;
reg [63:0]                wpairdata;
reg [31:0]                wpairdataq;
reg [63:0]                pairdata;
reg [1:0]                 wpcnt;
reg                       wpcnt_incr;
reg                       wpcnt_rst;

reg [`MEM_DATA_WIDTH-1:0] wxdata;
reg [`MEM_DATA_WIDTH-1:0] xordata;

wire [`MEM_ADDR_WIDTH-1:0] waddr;
reg [`MEM_ADDR_WIDTH-1:0] wpaddr;
reg [`MEM_ADDR_WIDTH-1:0] wxaddr;

wire                      wvalid, wvalid_snoop;
reg                       wpvalid;
reg                       wxvalid;

wire                      binary_search;
wire                      bsvalid;
wire [31:0]               bsdata;

reg [`MEM_DATA_WIDTH-1:0] data [3:0];
reg [`MEM_DATA_WIDTH-1:0] bdataq;
reg                       bvalidq;


wire [`EQUIHASH_c-1:0]    data_select;
reg  [`EQUIHASH_c-1:0]    collision_match;
reg  [2:0]                collision_cnt;

wire [`MEM_ADDR_WIDTH-1:0] stage_pair_end;
wire [`MEM_ADDR_WIDTH-1:0] stage_nxor_end;

assign data_select = bdata[`EQUIHASH_c-1:0];

assign collision_found = (data_select==collision_match && bvalid);
assign bstall = collision_found || cstore_stall || !binary_empty;
assign binary_search = (stage==`EQUIHASH_k);



wire [`MEM_ADDR_WIDTH-1:0] stage_nxor_size;

wire not_trivial_solutions;

`ifdef LOCAL_TESTBENCH
assign not_trivial_solutions = 1'b1;
`else
assign not_trivial_solutions = !(xordata[209:0]==210'h0);
`endif

always @(posedge eclk)
begin
  if (!rstb)
  begin
    cstore_state <= 4'b0;
  end
  else
  begin
    cstore_state <= cstore_state_next;
  end
end

always @(*)
begin : cstore_fsm
  cstore_stall = 1'b1;
  collision_store_done_valid = 1'b0;
  cstore_state_next = CSSTATE_IDLE;

  wpcnt_incr = 1'b0;
  wpcnt_rst = 1'b0;

  wpvalid = 1'b0;
  wpairdata = 64'h0;

  wxvalid = 1'b0;
  wxdata = 256'h0;

  case (cstore_state)
    CSSTATE_IDLE:
    begin
      cstore_stall = 1'b0;
      wpcnt_rst = 1'b0;
      if (!stream_empty)
      begin
        wpcnt_rst = 1'b1;
        cstore_state_next = CSSTATE_UNSTALL;
      end
    end
    CSSTATE_STALL:
    begin
      if (collision_cnt==3'h1)
        cstore_state_next = CSSTATE_PAIR01;
      else if (collision_cnt==3'h2)
        cstore_state_next = CSSTATE_PAIR02;
      else if (collision_cnt==3'h3)
        cstore_state_next = CSSTATE_PAIR03;
      else
        cstore_state_next = CSSTATE_UNSTALL;
      // 5 matches unsupported
    end
    CSSTATE_PAIR01:
    begin
      if (binary_empty && !memc_cmd_full)
      begin
        wpairdata = pairdata;
        wpvalid = 1'b1;
        cstore_state_next = CSSTATE_XOR01;
      end
      else
        cstore_state_next = CSSTATE_PAIR01;
    end
    CSSTATE_XOR01:
    begin
      if (!memc_cmd_full)
      begin
        wxdata = xordata;
        wxvalid = 1'b1;
        wpcnt_incr = 1'b1;
        cstore_state_next = CSSTATE_UNSTALL;
      end
      else
        cstore_state_next = CSSTATE_XOR01;
    end
    CSSTATE_PAIR02:
    begin
      if (binary_empty && !memc_cmd_full)
      begin
        wpairdata = pairdata;
        wpvalid = 1'b1;
        cstore_state_next = CSSTATE_XOR02;
      end
      else
        cstore_state_next = CSSTATE_PAIR02;
    end
    CSSTATE_XOR02:
    begin
      if (!memc_cmd_full)
      begin
        wxdata = xordata;
        wxvalid = 1'b1;
        wpcnt_incr = 1'b1;
        cstore_state_next = CSSTATE_PAIR12;
      end
      else
        cstore_state_next = CSSTATE_XOR02;
    end
    CSSTATE_PAIR12:
    begin
      if (binary_empty && !memc_cmd_full)
      begin
        wpairdata = pairdata;
        wpvalid = 1'b1;
        cstore_state_next = CSSTATE_XOR12;
      end
      else
        cstore_state_next = CSSTATE_PAIR12;
    end
    CSSTATE_XOR12:
    begin
      if (!memc_cmd_full)
      begin
        wxdata = xordata;
        wxvalid = 1'b1;
        wpcnt_incr = 1'b1;
        cstore_state_next = CSSTATE_UNSTALL;
      end
      else
        cstore_state_next = CSSTATE_XOR12;
    end
    CSSTATE_PAIR03:
    begin
      if (binary_empty && !memc_cmd_full)
      begin
        wpairdata = pairdata;
        wpvalid = 1'b1;
        cstore_state_next = CSSTATE_XOR03;
      end
      else
        cstore_state_next = CSSTATE_PAIR03;
    end
    CSSTATE_XOR03:
    begin
      if (!memc_cmd_full)
      begin
        wxdata = xordata;
        wxvalid = 1'b1;
        wpcnt_incr = 1'b1;
        cstore_state_next = CSSTATE_PAIR13;
      end
      else
        cstore_state_next = CSSTATE_XOR03;
    end
    CSSTATE_PAIR13:
    begin
      if (binary_empty && !memc_cmd_full)
      begin
        wpairdata = pairdata;
        wpvalid = 1'b1;
        cstore_state_next = CSSTATE_XOR13;
      end
      else
        cstore_state_next = CSSTATE_PAIR13;
    end
    CSSTATE_XOR13:
    begin
      if (!memc_cmd_full)
      begin
        wxdata = xordata;
        wxvalid = 1'b1;
        wpcnt_incr = 1'b1;
        cstore_state_next = CSSTATE_PAIR23;
      end
      else
        cstore_state_next = CSSTATE_XOR13;
    end
    CSSTATE_PAIR23:
    begin
      if (binary_empty && !memc_cmd_full)
      begin
        wpairdata = pairdata;
        wpvalid = 1'b1;
        cstore_state_next = CSSTATE_XOR23;
      end
      else
        cstore_state_next = CSSTATE_PAIR23;
    end
    CSSTATE_XOR23:
    begin
      if (!memc_cmd_full)
      begin
        wxdata = xordata;
        wxvalid = 1'b1;
        wpcnt_incr = 1'b1;
        cstore_state_next = CSSTATE_UNSTALL;
      end
      else
        cstore_state_next = CSSTATE_XOR23;
    end
    CSSTATE_UNSTALL:
    begin
      if (collision_found)
        cstore_state_next = CSSTATE_STALL;
      else if (stream_empty && dcr_empty && binary_empty && collision_stream_done)
        cstore_state_next = CSSTATE_DONE;
      else
        cstore_state_next = CSSTATE_UNSTALL;
      cstore_stall = 1'b0;
    end
    CSSTATE_DONE:
    begin
      cstore_state_next = CSSTATE_IDLE;
      collision_store_done_valid = 1'b1;
      cstore_stall = 1'b0;
    end
    default: cstore_state_next = CSSTATE_IDLE;
  endcase
end
// Pair Data
always @(*)
begin
  case (cstore_state)
    4'h2 : pairdata = {data[1][255:224],data[0][255:224]};
    4'h4 : pairdata = {data[2][255:224],data[0][255:224]};
    4'h6 : pairdata = {data[2][255:224],data[1][255:224]};
    4'h8 : pairdata = {data[3][255:224],data[0][255:224]};
    4'hA : pairdata = {data[3][255:224],data[1][255:224]};
    4'hC : pairdata = {data[3][255:224],data[2][255:224]};
    default : pairdata = {data[1][255:224],data[0][255:224]};
  endcase
end
always @(*)
begin
  case(wpcnt)
    2'h0:    wpdata = {wpdata256[255:64]  , wpairdata                  };
    2'h1:    wpdata = {wpdata256[255:128] , wpairdata, wpdata256[63:0] };
    2'h2:    wpdata = {wpdata256[255:192] , wpairdata, wpdata256[127:0]};
    default: wpdata = {                     wpairdata, wpdata256[191:0]};
  endcase
end
always @(posedge eclk)
begin
  if (!rstb)
    wpdata256 <= 256'h0;
  else if (wpvalid)
  begin
    if (wpcnt==2'h0)
      wpdata256 <= {wpdata256[255:64]  , wpairdata                  };
    else if (wpcnt==2'h1)
      wpdata256 <= {wpdata256[255:128] , wpairdata, wpdata256[63:0] };
    else if (wpcnt==2'h2)
      wpdata256 <= {wpdata256[255:192] , wpairdata, wpdata256[127:0]};
    else
      wpdata256 <= {                     wpairdata, wpdata256[191:0]};
  end
  else
    wpdata256 <= wpdata256;
end

always @(posedge eclk)
begin
  if (!rstb)
  begin
    wpcnt <= 2'h0;
    wpaddr <= 32'h0;
    wxaddr <= 32'h0;
    wpairdataq <= 32'h0;
  end
  else
  begin
    if (wpcnt_rst)
      wpcnt <= stage_pair_base[1:0];
    else if (wpcnt_incr && wpcnt==3'h3 && not_trivial_solutions)
      wpcnt <= 2'h0;
    else if (wpcnt_incr && not_trivial_solutions)
      wpcnt <= wpcnt + 2'h1;
    else
      wpcnt <= wpcnt;

    if (wpcnt_rst)
      wpaddr <= stage_pair_base;
    else if (wpcnt_incr && not_trivial_solutions)
      wpaddr <= wpaddr + 32'h1;
    else
      wpaddr <= wpaddr;

    if (wpcnt_rst)
      wxaddr <= stage_nxor_base;
    else if (wpcnt_incr)
      wxaddr <= wxaddr + 32'h1;
    else
      wxaddr <= wxaddr;

    if (wpvalid)
      wpairdataq <= wpairdata[63:32];
    else
      wpairdataq <= wpairdataq;

    if (collision_store_done_valid)
      collision_store_done <= 1'b1;
    else
      collision_store_done <= 1'b0;
  end
end
// XOR Data
always @(*)
begin
  case (cstore_state)  //{32 Pair Ponter, 14 Padding,210 XOR data}
    4'h3 : xordata = {wpaddr,14'h0,data[1][209:0]^data[0][209:0]};
    4'h5 : xordata = {wpaddr,14'h0,data[2][209:0]^data[0][209:0]};
    4'h7 : xordata = {wpaddr,14'h0,data[2][209:0]^data[1][209:0]};
    4'h9 : xordata = {wpaddr,14'h0,data[3][209:0]^data[0][209:0]};
    4'hB : xordata = {wpaddr,14'h0,data[3][209:0]^data[1][209:0]};
    4'hD : xordata = {wpaddr,14'h0,data[3][209:0]^data[2][209:0]};
    default : xordata = {wpaddr,14'h0,data[0][209:0]^data[1][209:0]};
  endcase
end

//Collision detection and xor data buffering
always @(posedge eclk)
begin
  if (!rstb)
  begin
    collision_match <= 16'hABCD; //fix so first read can't be a match
    collision_cnt <= 3'h0;
  end
  else
  begin
    //collision_match
    if (bvalid)
      collision_match <= bdata[`EQUIHASH_c-1:0];
    else if (collision_store_done_valid)
      collision_match <= 16'hABCD;
    else
      collision_match <= collision_match;

    //collision_found
    if (wpcnt_rst)
      collision_cnt <= 3'h0;
    else if (bvalid)
    begin
      if (collision_found)
        collision_cnt <= collision_cnt + 3'h1;
      else
        collision_cnt <= 3'h0;
    end
    else
      collision_cnt <= collision_cnt;
  end
end

integer i;
always @(posedge eclk)
begin
  if (!rstb)
  begin
    for (i=0;i<4;i=i+1)
      data[i] <= `MEM_DATA_WIDTH'hFFFF;
  end
  else
  begin
    for (i=0;i<4;i=i+1)
    begin
      if (i==collision_cnt[1:0] && bvalidq)
        data[i] <= {bdataq[255:224],14'h0,21'h0,bdataq[209:21]}; // Preserve 32 index/pair pointer & shift data >>  21
      else
        data[i] <= data[i];
    end

    bdataq <= bdata;
    bvalidq <= bvalid;
  end
end

// wxvalid & wpvalid clamp
  wire wxvalidc;
  assign wxvalidc = wxvalid && (wxaddr < stage_nxor_limit) && not_trivial_solutions; //MEM_BUF1
// Output Assignments
  assign stage_pair_end = wpaddr;
  assign stage_nxor_end = (wxaddr==stage_nxor_base) ? wxaddr : (wxaddr <= stage_nxor_limit) ? wxaddr - 32'h1 : (stage_nxor_limit-32'h1);

  assign wvalid = (cstore_state[0]) ? wxvalidc && !binary_search : wpvalid && !binary_search; //disable wvalid during final stage
  assign wvalid_snoop = (cstore_state[0]) ? wxvalidc && !binary_search : 1'b0;  //Only trigger for XOR writing
  assign wdata  = (cstore_state[0]) ? wxdata  : wpdata;
  assign waddr  = (cstore_state[0]) ? wxaddr  : {2'h0,wpaddr[31:2]}; // Write to 256bit aligned address

  assign bsvalid = binary_search && not_trivial_solutions && (wxvalidc|| wpvalid);
  assign bsdata = (cstore_state[0]) ? wpairdataq : wpairdata[31:0];
endmodule  //collision_store
