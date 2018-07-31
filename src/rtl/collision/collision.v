/* © Copyright ePIC Blockchain Technologies Inc. (2018).  All Rights Reserved.
 * Written by emai <emai@epicblockchain.io> June 2018
 */

/* "collision" block traverses through the radix sorted data finding collisions.
 * A stream_buffer FIFO is used to feed the collision_store and binary_search
 * FIFO aids in traverising the binary tree of collision pairs.  The logic is
 * controlled by the collision read state machine (collision_rfsm) and binary
 * search read state machine (binarysearch_rfsm) each controlling a read port
 * that is muxxed together.
 */

`include "equihash_defines.v"

module collision(
                   input             eclk,
                   input             rstb,

                   input [3:0]       stage,
                   input             memc_cmd_full,

                   input             collision_start,
                   output            collision_done,

                   // Read Port memory - r0 XOR, r1 PAIR
                   output [`MEM_ADDR_WIDTH-1:0] raddr,
                   output [3:0]                 rtag,
                   output                       rsend,

                   input [`MEM_DATA_WIDTH-1:0]  rdata,
                   input                        rvalid,

                   // Write Port Memory
                   output [`MEM_ADDR_WIDTH-1:0] waddr,
                   output [3:0]                 wtag,
                   output [`MEM_DATA_WIDTH-1:0] wdata,
                   output                       wvalid,
                   output                       wvalid_snoop,

                   // Write Pair Location
                   input [`MEM_ADDR_WIDTH-1:0]  stage_pair_base, //64bit aligned address
                   output[`MEM_ADDR_WIDTH-1:0]  stage_pair_end,  //64bit aligned address

                   // Read XOR Location
                   input [`MEM_ADDR_WIDTH-1:0]  stage_cxor_base,
                   input [`MEM_ADDR_WIDTH-1:0]  stage_cxor_end,

                   // Write XOR Location
                   input [`MEM_ADDR_WIDTH-1:0]  stage_nxor_base,
                   output [`MEM_ADDR_WIDTH-1:0] stage_nxor_end,
                   input [`MEM_ADDR_WIDTH-1:0]  stage_nxor_limit,

                   output                       uart_start,
                   output [63:0]                uart_tdata,
                   output                       uart_headernonce_send

                );

  localparam RSTATE_IDLE      = 3'h0;
  localparam RSTATE_PASS      = 3'h1;
  localparam RSTATE_PASS_END0 = 3'h2;
  localparam RSTATE_PASS_END1 = 3'h3;
  localparam RSTATE_DONE      = 3'h4;

  localparam BSSTATE_IDLE      = 3'h0;
  localparam BSSTATE_PASS      = 3'h1;
  localparam BSSTATE_PASS_END0 = 3'h2;
  localparam BSSTATE_PASS_END1 = 3'h3;
  localparam BSSTATE_DONE      = 3'h4;

  reg collision_done;
  reg collision_stream_done;
  reg collision_done_valid;
  reg collision_stream_done_valid;
  wire collision_store_done;

  reg [2:0] collision_rstate;
  reg [2:0] collision_rstate_next;

  reg [2:0] binarysearch_rstate;
  reg [2:0] binarysearch_rstate_next;

  reg read_cnt_rst;
  reg read_cnt_incr;
  reg [`MEM_ADDR_WIDTH-1:0] read_cnt;
  wire [`MEM_ADDR_WIDTH-1:0] read_end;

  wire [`MEM_DATA_WIDTH-1:0] bdata;
  wire         bstall;
  reg bvalid;
  wire stream_empty,stream_full,stream_watermark, dcr_empty;
  wire binary_empty;

  wire [`MEM_ADDR_WIDTH-1:0] bsdata;
  wire                       bsvalid;


  wire collision_start;
  wire [`MEM_ADDR_WIDTH-1:0] stage_pair_base;
  wire [`MEM_ADDR_WIDTH-1:0] stage_pair_end;
  wire [`MEM_ADDR_WIDTH-1:0] stage_nxor_base;
  wire [`MEM_ADDR_WIDTH-1:0] stage_nxor_end;

  wire [`MEM_ADDR_WIDTH-1:0] waddr;
  wire [`MEM_DATA_WIDTH-1:0] wdata;
  wire                       wvalid, wvalid_snoop;
  wire [3:0]                 wtag;

  wire rsend;
  wire [`MEM_ADDR_WIDTH-1:0] raddr, r0addr, r1addr;
  wire rvalid, r1valid,r0valid;
  wire [`MEM_DATA_WIDTH-1:0] rdata, r1data, r0data;

  wire uart_start;
  wire [511:0] uart_data;

  // Debit Credit Read Control
  reg [`DC_WIDTH-1:0] dcr_cnt;
  wire                dcr_stall;
  always @(posedge eclk)
  begin
    if (!rstb)
      dcr_cnt <= `DC_WIDTH'h0;
    else if (rsend && rvalid)
      dcr_cnt <= dcr_cnt;
    else if (rsend)
      dcr_cnt <= dcr_cnt + `DC_WIDTH'h1;
    else if (rvalid)
      dcr_cnt <= dcr_cnt - `DC_WIDTH'h1;
    else
      dcr_cnt <= dcr_cnt;
  end
  assign dcr_stall = (dcr_cnt == `DCR_LIMIT);
  assign dcr_empty = (dcr_cnt==`DC_WIDTH'h0);
  assign read_end = stage_cxor_end + 32'h1;

  always @(posedge eclk)
  begin
    if (!rstb)
    begin
      collision_rstate <= 3'b0;
      binarysearch_rstate <= 3'b0;
    end
    else
    begin
      collision_rstate <= collision_rstate_next;
      binarysearch_rstate <= binarysearch_rstate_next;
    end
  end

  assign collision_busy = collision_rstate!=RSTATE_IDLE;
  always @(*)
  begin : collision_rfsm
    read_cnt_incr = 1'b0;
    read_cnt_rst = 1'b0;
    collision_done_valid = 1'b0;
    collision_stream_done_valid = 1'b0;
    collision_rstate_next = RSTATE_IDLE;
    case (collision_rstate)
      RSTATE_IDLE:
      begin
        read_cnt_rst = 1'b1;
        if (collision_start)
          collision_rstate_next = RSTATE_PASS;
      end
      RSTATE_PASS:
      begin
        if (read_cnt==read_end && !dcr_stall)
        begin
          read_cnt_incr = 1'b0;
          collision_rstate_next = RSTATE_PASS_END0;
        end
        else
        begin
          read_cnt_incr = 1'b1 && !stream_watermark && binary_empty && !dcr_stall && !bs_busy && !wvalid && !memc_cmd_full;
          collision_rstate_next = RSTATE_PASS;
        end
      end
      RSTATE_PASS_END0:
      begin
        if (stream_empty && dcr_empty)
          collision_rstate_next = RSTATE_PASS_END1;
        else
          collision_rstate_next = RSTATE_PASS_END0;
      end
      RSTATE_PASS_END1:
      begin
        collision_stream_done_valid = 1'b1;
        if (collision_store_done)  //fix
        begin
          read_cnt_rst = 1'b1;
          collision_rstate_next = RSTATE_DONE;
        end
        else
          collision_rstate_next = RSTATE_PASS_END1;
      end
      RSTATE_DONE:
      begin
        if (!bs_busy)
        begin
          read_cnt_rst = 1'b1;
          collision_done_valid = 1'b1;
          collision_rstate_next = RSTATE_IDLE;
        end
        else
          collision_rstate_next = RSTATE_DONE;
      end
    default: collision_rstate_next = RSTATE_IDLE;
    endcase
  end

  always @(posedge eclk)
  begin
    if (!rstb)
    begin
      read_cnt <=  `MEM_ADDR_WIDTH'h0;
      collision_done <= 1'b0;
      collision_stream_done <= 1'b0;
    end
    else
    begin
      //read_cnt
      if (read_cnt_rst)
        read_cnt <= stage_cxor_base;
      else if (read_cnt_incr)
        read_cnt <= read_cnt + `MEM_ADDR_WIDTH'h1;
      else
        read_cnt <= read_cnt;

      //collision_stream_done
      if (collision_stream_done_valid)
        collision_stream_done <= 1'b1;
      else
        collision_stream_done <= 1'b0;

      //collision_done
      if (collision_done_valid)
        collision_done <= 1'b1;
      else
        collision_done <= 1'b0;
    end
  end

  always @(posedge eclk)
  begin
    bvalid <= !stream_empty && !bstall;
  end

  ring_buffer stream_buffer (
      .data_out(bdata),
      .data_count(),
      .empty(stream_empty),
      .full(),
      .almst_empty(),
      .almst_full(stream_watermark),
      .err(),
      .data_in(r0data),
      .wr_en(r0valid),
      .rd_en(!stream_empty && !bstall),
      .rstb(rstb),
      .eclk(eclk)
      );

  collision_store collision_store (
    .eclk(eclk),
    .rstb(rstb),

    .stage(stage),
    .memc_cmd_full(memc_cmd_full),

    .collision_start(collision_start),
    .collision_stream_done(collision_stream_done),
    .collision_store_done (collision_store_done),
    .dcr_empty(dcr_empty),
    .stream_empty(stream_empty),
    .binary_empty(binary_empty),

    .bdata(bdata),
    .bvalid(bvalid),

    .bstall(bstall),

    .stage_pair_base(stage_pair_base),
    .stage_pair_end (stage_pair_end),

    // Write XOR Location
    .stage_nxor_base(stage_nxor_base),
    .stage_nxor_end(stage_nxor_end),
    .stage_nxor_limit(stage_nxor_limit),

    .bsvalid(bsvalid),
    .bsdata(bsdata),

    .wvalid(wvalid),
    .wvalid_snoop(wvalid_snoop),
    .waddr(waddr),
    .wdata(wdata)

  );

  reg bsready, r1validq;
  reg bsleaf,bsleafq;
  reg bempty;
  reg r1send_go;
  wire uart_headernonce_send;
  reg [31:0] bswdataq , bswdata32U, bswdata32L;
  wire [`MEM_ADDR_WIDTH-1:0] bsraddr;
  wire bswvalid;
  reg bsrsend, bsrsendq;
  wire bs_busy;
  reg [63:0] uart_tdata64;
  wire bswsend;
  wire [31:0] bswdata;

  assign bswvalid = (bsleaf) ? 1'b0 : (r1valid || r1validq); //2 write pulses
  assign bs_busy = (binarysearch_rstate != BSSTATE_IDLE);

  always @(posedge eclk)
  begin
    if (!rstb)
    begin
      bsleafq <= 1'b0;
      bsready <= 1'b0;
      bsrsendq <= 1'b0;
      r1validq <= 1'b0;
      bswdataq <= `MEM_DATA_WIDTH'h0;
      bempty <= 1'b1;
    end
    else
    begin
      bsleafq <= bsleaf;
      bempty <= binary_empty;
      if (bsrsend)
        bsready <= 1'b1;
      else if (r1send_go)
        bsready <= 1'b0;
      else
        bsready <= bsready;

      bsrsendq <= bsrsend;
      r1validq <= r1valid;
      bswdataq <= bswdata32U;
    end
  end
  always @(r1valid)
  begin
    case (bsraddr[1:0])
      2'h0 :    begin bsleaf = (r1data[ 31: 22]==10'h3FF) && (r1data[ 63: 54]==10'h3FF); bswdata32U = r1data[ 63: 32]; bswdata32L = r1data[ 31:  0]; end
      2'h1 :    begin bsleaf = (r1data[ 95: 86]==10'h3FF) && (r1data[127:118]==10'h3FF); bswdata32U = r1data[127: 96]; bswdata32L = r1data[ 95: 64]; end
      2'h2 :    begin bsleaf = (r1data[159:150]==10'h3FF) && (r1data[191:182]==10'h3FF); bswdata32U = r1data[191:160]; bswdata32L = r1data[159:128]; end
      2'h3 :    begin bsleaf = (r1data[223:214]==10'h3FF) && (r1data[255:246]==10'h3FF); bswdata32U = r1data[255:224]; bswdata32L = r1data[223:192]; end
      default : begin bsleaf = (r1data[ 31: 22]==10'h3FF) && (r1data[ 63: 54]==10'h3FF); bswdata32U = r1data[ 63: 32]; bswdata32L = r1data[ 31:  0]; end
    endcase
  end

  always @(r1valid)
  begin
    case (bsraddr[1:0])
      2'h0 :    uart_tdata64 =  {10'h0, r1data[ 53: 32], 10'h0 , r1data[ 21:  0] };
      2'h1 :    uart_tdata64 =  {10'h0, r1data[117: 96], 10'h0 , r1data[ 85: 64] };
      2'h2 :    uart_tdata64 =  {10'h0, r1data[181:160], 10'h0 , r1data[149:128] };
      2'h3 :    uart_tdata64 =  {10'h0, r1data[245:224], 10'h0 , r1data[213:192] };
      default : uart_tdata64 =  {10'h0, r1data[ 53: 32], 10'h0 , r1data[ 21:  0] };
    endcase
  end

  assign bswsend = bsvalid || (r1valid && !bsleaf) || (r1validq && !bsleafq);
  assign bswdata = bsvalid ? bsdata : ( (r1valid) ? bswdata32L : bswdata32U );
  ring_buffer #(9,32, 512, 3, 3) binary_search (
      .data_out(bsraddr),
      .data_count(),
      .empty(binary_empty),
      .full(),
      .almst_empty(),
      .almst_full(),
      .err(),
      .data_in(bswdata),
      .wr_en(bswsend),
      .rd_en(bsrsend),
      .rstb(rstb),
      .eclk(eclk)
      );


  always @(*)
  begin : binarysearch_rfsm
    bsrsend = 1'b0;
    r1send_go = 1'b0;
    binarysearch_rstate_next = RSTATE_IDLE;
    case (binarysearch_rstate)
      BSSTATE_IDLE:
      begin
        if (!binary_empty && dcr_empty)
        begin
          bsrsend = 1'b1;
          binarysearch_rstate_next = BSSTATE_PASS;
        end
      end
      BSSTATE_PASS:
      begin
        if (bsready && !memc_cmd_full)
        begin
          r1send_go = 1'b1;
          binarysearch_rstate_next = BSSTATE_PASS;
        end
        else if (r1valid)
          binarysearch_rstate_next = BSSTATE_PASS_END0;
        else
          binarysearch_rstate_next = BSSTATE_PASS;
      end
      BSSTATE_PASS_END0:
      begin
        if (!binary_empty)
        begin
          bsrsend = 1'b1;
          binarysearch_rstate_next = BSSTATE_PASS;
        end
        else
          binarysearch_rstate_next = BSSTATE_PASS_END1;
      end
      BSSTATE_PASS_END1:
      begin
        binarysearch_rstate_next = BSSTATE_DONE;
      end
      BSSTATE_DONE:
      begin
        binarysearch_rstate_next = BSSTATE_IDLE;
      end
      default: binarysearch_rstate_next = BSSTATE_IDLE;
    endcase
  end

//Output Assignments
assign r0send = read_cnt_incr;
assign r0addr = read_cnt;

assign r1send = r1send_go;
assign r1addr = {2'b0,bsraddr[31:2]}; // Pair data is stored in 64bit alignment

assign rsend = (bs_busy) ? r1send : r0send;
assign raddr = (bs_busy) ? r1addr : r0addr;

assign r0valid = (bs_busy) ? 1'b0 : rvalid;
assign r1valid = (bs_busy) ? rvalid : 1'b0;
assign r0data =  (bs_busy) ? `MEM_DATA_WIDTH'h0 : rdata;
assign r1data =  (bs_busy) ? rdata : `MEM_DATA_WIDTH'h0;

assign uart_tdata = uart_tdata64;
assign uart_start = bsleaf && r1valid;

assign uart_headernonce_send = (!binary_empty && bempty);

assign wtag = 4'h3;
endmodule //collision
