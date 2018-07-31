/* © Copyright ePIC Blockchain Technologies Inc. (2018).  All Rights Reserved.
 * Written by emai <emai@epicblockchain.io> June 2018
 */

`include "equihash_defines.v"

module equihash (
  input             eclk,
  input             rstb,

  // UART RX/TX information
  input             uart_done,
  input [479:0]     uart_rdata,

  output            uart_start,
  output [63:0]     uart_tdata,
  output            uart_headernonce_send,

  input                           memc_init_done,

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

  output                          equihash_state_done

  /*
  // AXI write address channel signals
   input                               axi_wready, // Indicates slave is ready to accept a
   output [C_AXI_ID_WIDTH-1:0]         axi_wid,    // Write ID
   output [C_AXI_ADDR_WIDTH-1:0]       axi_waddr,  // Write address
   output [7:0]                        axi_wlen,   // Write Burst Length
   output [2:0]                        axi_wsize,  // Write Burst size
   output [1:0]                        axi_wburst, // Write Burst type
   output [1:0]                        axi_wlock,  // Write lock type
   output [3:0]                        axi_wcache, // Write Cache type
   output [2:0]                        axi_wprot,  // Write Protection type
   output                              axi_wvalid, // Write address valid

// AXI write data channel signals
   input                               axi_wd_wready,  // Write data ready
   output [C_AXI_ID_WIDTH-1:0]         axi_wd_wid,     // Write ID tag
   output [C_AXI_DATA_WIDTH-1:0]       axi_wd_data,    // Write data
   output [C_AXI_DATA_WIDTH/8-1:0]     axi_wd_strb,    // Write strobes
   output                              axi_wd_last,    // Last write transaction
   output                              axi_wd_valid,   // Write valid

// AXI write response channel signals
   input  [C_AXI_ID_WIDTH-1:0]         axi_wd_bid,     // Response ID
   input  [1:0]                        axi_wd_bresp,   // Write response
   input                               axi_wd_bvalid,  // Write reponse valid
   output                              axi_wd_bready,  // Response ready

// AXI read address channel signals
   input                               axi_rready,     // Read address ready
   output [C_AXI_ID_WIDTH-1:0]         axi_rid,        // Read ID
   output [C_AXI_ADDR_WIDTH-1:0]       axi_raddr,      // Read address
   output [7:0]                        axi_rlen,       // Read Burst Length
   output [2:0]                        axi_rsize,      // Read Burst size
   output [1:0]                        axi_rburst,     // Read Burst type
   output [1:0]                        axi_rlock,      // Read lock type
   output [3:0]                        axi_rcache,     // Read Cache type
   output [2:0]                        axi_rprot,      // Read Protection type
   output                              axi_rvalid,     // Read address valid

// AXI read data channel signals
   input  [C_AXI_ID_WIDTH-1:0]         axi_rd_bid,     // Response ID
   input  [1:0]                        axi_rd_rresp,   // Read response
   input                               axi_rd_rvalid,  // Read reponse valid
   input  [C_AXI_DATA_WIDTH-1:0]       axi_rd_data,    // Read data
   input                               axi_rd_last,    // Read last
   output                              axi_rd_rready   // Read Response ready
   */
  );


// Connectivity Signals
wire eclk;
wire rstb;

// equihash_state
wire blake2b_start;
wire blake2b_done;
wire radix_start;
wire radix_done;
wire collision_start;
wire collision_done;
wire [3:0] stage;
wire [2:0] state;
wire equihash_state_done;

// snoop
wire snoop_rst;
wire [3:0] snoop_pass;
wire snoop_pass_cnt0;

wire [`MEM_ADDR_WIDTH-1:0] bucket0_base;
wire [`MEM_ADDR_WIDTH-1:0] bucket1_base;
wire [`MEM_ADDR_WIDTH-1:0] bucket2_base;
wire [`MEM_ADDR_WIDTH-1:0] bucket3_base;
wire [`MEM_ADDR_WIDTH-1:0] bucket4_base;
wire [`MEM_ADDR_WIDTH-1:0] bucket5_base;
wire [`MEM_ADDR_WIDTH-1:0] bucket6_base;
wire [`MEM_ADDR_WIDTH-1:0] bucket7_base;
wire [`MEM_ADDR_WIDTH-1:0] bucket8_base;
wire [`MEM_ADDR_WIDTH-1:0] bucket9_base;
wire [`MEM_ADDR_WIDTH-1:0] bucketA_base;
wire [`MEM_ADDR_WIDTH-1:0] bucketB_base;
wire [`MEM_ADDR_WIDTH-1:0] bucketC_base;
wire [`MEM_ADDR_WIDTH-1:0] bucketD_base;
wire [`MEM_ADDR_WIDTH-1:0] bucketE_base;
wire [`MEM_ADDR_WIDTH-1:0] bucketF_base;

// Write Memory ports (3)
wire [3:0]                 wbtag, wctag, wrtag;
wire [`MEM_ADDR_WIDTH-1:0] wbaddr, wcaddr, wraddr;
wire [`MEM_DATA_WIDTH-1:0] wbdata, wcdata, wrdata, wsdata;
wire                       wbvalid, wcvalid, wrvalid, wsvalid, wcvalid_snoop;

// Read Memory ports (2)
wire [3:0]                 rctag, rrtag;
wire [`MEM_ADDR_WIDTH-1:0] rcaddr, rraddr;
wire                       rcsend, rrsend;
wire [`MEM_DATA_WIDTH-1:0] rcdata, rrdata;
wire                       rcvalid, rrvalid;

wire [`MEM_ADDR_WIDTH-1:0] blake2b_base_addr;
wire [`MEM_ADDR_WIDTH-1:0] radix_base_addr;
wire [`MEM_ADDR_WIDTH-1:0] radix_scratch_addr;
wire [`MEM_ADDR_WIDTH-1:0] radix_end;
wire [`MEM_ADDR_WIDTH-1:0] stage_pair_base;
wire [`MEM_ADDR_WIDTH-1:0] stage_pair_end;
wire [`MEM_ADDR_WIDTH-1:0] stage_cxor_base;
wire [`MEM_ADDR_WIDTH-1:0] stage_cxor_end;
wire [`MEM_ADDR_WIDTH-1:0] stage_nxor_base;
wire [`MEM_ADDR_WIDTH-1:0] stage_nxor_end;
wire [`MEM_ADDR_WIDTH-1:0] stage_nxor_limit;

wire [63:0]                uart_tdata;
wire                       uart_start;
wire                       uart_headernonce_send;

// The memory gasket
mem_gasket mem_gasket(
  .eclk(eclk),
  .rstb(rstb),

  .state(state),

  .memc_cmd_full(memc_cmd_full), //i

  .memc_cmd_en(memc_cmd_en),
  .memc_cmd_instr(memc_cmd_instr),
  .memc_cmd_bl(memc_cmd_bl),
  .memc_cmd_addr(memc_cmd_addr),

  .memc_wr_en(memc_wr_en),
  .memc_wr_end(memc_wr_end),

  .memc_wr_mask(memc_wr_mask),
  .memc_wr_data(memc_wr_data),
  .memc_wr_full(memc_wr_full), //Should never hit full

  .memc_rd_en(memc_rd_en), // TIE TO 1'b1
  .memc_rd_data(memc_rd_data),   //ensure data is flopped
  .memc_rd_empty(memc_rd_empty), //Generate rvalid from this

  .wbaddr(wbaddr),
  .wbdata(wbdata),
  .wbvalid(wbvalid),

  .wraddr(wraddr),
  .wrdata(wrdata),
  .wrvalid(wrvalid),

  .wcaddr(wcaddr),
  .wcdata(wcdata),
  .wcvalid(wcvalid),

  .rraddr(rraddr),
  .rrsend(rrsend),

  .rrdata(rrdata),
  .rrvalid(rrvalid),

  .rcaddr(rcaddr),
  .rcsend(rcsend),

  .rcdata(rcdata),
  .rcvalid(rcvalid)
  );

// The equihash_state core
equihash_state equihash_state(
  .eclk(eclk),
  .rstb(rstb),

  .init_done(memc_init_done),

  .stage(stage),
  .state(state),

  .uart_done(uart_done),

  .blake2b_start(blake2b_start),
  .blake2b_done(blake2b_done),

  .radix_start(radix_start),
  .radix_done(radix_done),

  .collision_start(collision_start),
  .collision_done(collision_done),

  .snoop_pass_cnt0(snoop_pass_cnt0),

  .blake2b_base_addr (blake2b_base_addr),

  .radix_base_addr   (radix_base_addr),
  .radix_scratch_addr(radix_scratch_addr),
  .radix_end         (radix_end),

  .stage_cxor_base   (stage_cxor_base),
  .stage_cxor_end    (stage_cxor_end),

  .stage_nxor_base   (stage_nxor_base),
  .stage_nxor_end    (stage_nxor_end),
  .stage_nxor_limit  (stage_nxor_limit),

  .stage_pair_base   (stage_pair_base),
  .stage_pair_end    (stage_pair_end),

  .equihash_state_done(equihash_state_done)

  );

// The blake2b core
`ifdef LOCAL_TESTBENCH
  blake2b #(.NUM_INDEX(21'hF) )blake2b (
`else
  blake2b #(.NUM_INDEX(21'h1FFFFF) )blake2b (
`endif
  .eclk(eclk),
  .rstb(rstb),

  .memc_cmd_full(memc_cmd_full),

  .blake2b_start(blake2b_start),
  .blake2b_done(blake2b_done),

  .blake2b_base_addr(blake2b_base_addr),

  .uart_done(uart_done),
  .uart_rdata(uart_rdata),

  .waddr(wbaddr),
  .wdata(wbdata),
  .wtag(wbtag),
  .wvalid(wbvalid)

  );

// The snoop core
assign wsvalid = wbvalid || wrvalid || wcvalid_snoop;//fixme gate wcvalid when writing XOR only
assign wsdata = (wbvalid) ? wbdata : ((wrvalid) ? wrdata : wcdata);

snoop snoop (
  .eclk(eclk),
  .rstb(rstb),

  .stage(stage),

  .pass_cnt(snoop_pass),
  .pass_cnt0(snoop_pass_cnt0),
  .bucket_cnt_rst(snoop_rst),

  .bucket0_base(bucket0_base),
  .bucket1_base(bucket1_base),
  .bucket2_base(bucket2_base),
  .bucket3_base(bucket3_base),
  .bucket4_base(bucket4_base),
  .bucket5_base(bucket5_base),
  .bucket6_base(bucket6_base),
  .bucket7_base(bucket7_base),
  .bucket8_base(bucket8_base),
  .bucket9_base(bucket9_base),
  .bucketA_base(bucketA_base),
  .bucketB_base(bucketB_base),
  .bucketC_base(bucketC_base),
  .bucketD_base(bucketD_base),
  .bucketE_base(bucketE_base),
  .bucketF_base(bucketF_base),

  .wvalid(wsvalid),
  .wdata(wsdata)
  );

// The radix core
radix radix (
  .eclk(eclk),
  .rstb(rstb),
  .stage(stage),
  .memc_cmd_full(memc_cmd_full),

  .radix_start(radix_start),

  .radix_done(radix_done),
  .radix_result_addr(),

  // Data Pointers
  .radix_base_addr   (radix_base_addr),
  .radix_scratch_addr(radix_scratch_addr),
  .radix_end         (radix_end),
  .radix_size        (3'b0),

  .bucket0_base(bucket0_base),
  .bucket1_base(bucket1_base),
  .bucket2_base(bucket2_base),
  .bucket3_base(bucket3_base),
  .bucket4_base(bucket4_base),
  .bucket5_base(bucket5_base),
  .bucket6_base(bucket6_base),
  .bucket7_base(bucket7_base),
  .bucket8_base(bucket8_base),
  .bucket9_base(bucket9_base),
  .bucketA_base(bucketA_base),
  .bucketB_base(bucketB_base),
  .bucketC_base(bucketC_base),
  .bucketD_base(bucketD_base),
  .bucketE_base(bucketE_base),
  .bucketF_base(bucketF_base),
  // Read Port memory
  .raddr(rraddr),
  .rtag(rrtag),
  .rsend(rrsend),

  .rdata(rrdata),
  .rvalid(rrvalid),

  // Write Port Memory
  .waddr(wraddr),
  .wdata(wrdata),
  .wtag(wrtag),
  .wvalid(wrvalid),

  .snoop_rst(snoop_rst),
  .snoop_pass(snoop_pass)
  );

  // The collision core
  collision collision (
    .eclk(eclk),
    .rstb(rstb),
    .stage(stage),
    .memc_cmd_full(memc_cmd_full),

    .collision_start(collision_start),
    .collision_done(collision_done),

    // Read Port memory
    .raddr(rcaddr),
    .rtag(rctag),
    .rsend(rcsend),

    .rdata(rcdata),
    .rvalid(rcvalid),

    // Write Port Memory
    .waddr(wcaddr),
    .wdata(wcdata),
    .wtag(wctag),
    .wvalid(wcvalid),
    .wvalid_snoop(wcvalid_snoop),

    .stage_pair_base  (stage_pair_base),
    .stage_pair_end   (stage_pair_end),

    .stage_cxor_base   (stage_cxor_base),
    .stage_cxor_end    (stage_cxor_end),

    .stage_nxor_base   (stage_nxor_base),
    .stage_nxor_end    (stage_nxor_end),
    .stage_nxor_limit  (stage_nxor_limit),

    .uart_start(uart_start),
    .uart_tdata(uart_tdata),
    .uart_headernonce_send(uart_headernonce_send)

  );

endmodule //equihash
