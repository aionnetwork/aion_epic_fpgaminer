/* © Copyright ePIC Blockchain Technologies Inc. (2018).  All Rights Reserved.
 * Written by emai <emai@epicblockchain.io> June 2018
 */

/* "radix" block is controlled by the RADIX_PASS & RADIX_BITS parameters which
 * control the number of loops must be performed to sort the data.  RADIX_BITS
 * should be set to the same value as the "snoop" block.  Each pass sorts the
 * data using 1 scratch surface.  If the number of passes is odd, the scratch
 * surface contains the sorted data else final data is contained in the original
 * surface.
 */

`include "equihash_defines.v"

module radix(
                   input             eclk,
                   input             rstb,

                   input [3:0]       stage,
                   input             memc_cmd_full,

                   input             radix_start,
                   output            radix_done,
                   output [`MEM_ADDR_WIDTH-1:0] radix_result_addr, //unused for Aion


                   // Data Pointers
                   input [`MEM_ADDR_WIDTH-1:0] radix_base_addr,
                   input [`MEM_ADDR_WIDTH-1:0] radix_scratch_addr,
                   input [`MEM_ADDR_WIDTH-1:0] radix_end,
                   input [2:0]                 radix_size,

                   // Bucket Pointers
                   input [`MEM_ADDR_WIDTH-1:0] bucket0_base,
                   input [`MEM_ADDR_WIDTH-1:0] bucket1_base,
                   input [`MEM_ADDR_WIDTH-1:0] bucket2_base,
                   input [`MEM_ADDR_WIDTH-1:0] bucket3_base,
                   input [`MEM_ADDR_WIDTH-1:0] bucket4_base,
                   input [`MEM_ADDR_WIDTH-1:0] bucket5_base,
                   input [`MEM_ADDR_WIDTH-1:0] bucket6_base,
                   input [`MEM_ADDR_WIDTH-1:0] bucket7_base,
                   input [`MEM_ADDR_WIDTH-1:0] bucket8_base,
                   input [`MEM_ADDR_WIDTH-1:0] bucket9_base,
                   input [`MEM_ADDR_WIDTH-1:0] bucketA_base,
                   input [`MEM_ADDR_WIDTH-1:0] bucketB_base,
                   input [`MEM_ADDR_WIDTH-1:0] bucketC_base,
                   input [`MEM_ADDR_WIDTH-1:0] bucketD_base,
                   input [`MEM_ADDR_WIDTH-1:0] bucketE_base,
                   input [`MEM_ADDR_WIDTH-1:0] bucketF_base,

                   // Read Port memory
                   output [`MEM_ADDR_WIDTH-1:0] raddr,
                   output [3:0]                 rtag,
                   output                       rsend,

                   input [`MEM_DATA_WIDTH-1:0]  rdata,
                   input                        rvalid,

                   // Write Port Memory
                   output [`MEM_ADDR_WIDTH-1:0] waddr,
                   output [`MEM_DATA_WIDTH-1:0] wdata,
                   output [3:0]                 wtag,
                   output                       wvalid,

                   output snoop_rst,
                   output [3:0] snoop_pass

                   );

  parameter RADIX_PASS = 6; // ceil(EQUIHASH_c / RADIX_BITS)
  parameter RADIX_BITS = 4;

  localparam RSTATE_IDLE      = 3'h0;
  localparam RSTATE_PASS      = 3'h1;
  localparam RSTATE_PASS_END  = 3'h2;
  localparam RSTATE_DONE      = 3'h3;

  localparam WSTATE_IDLE      = 3'h0;
  localparam WSTATE_PASS      = 3'h1;
  localparam WSTATE_PASS_END0 = 3'h2;
  localparam WSTATE_PASS_END1 = 3'h3;
  localparam WSTATE_DONE      = 3'h4;

  reg radix_done;

  reg  [`MEM_ADDR_WIDTH-1:0] waddr;
  wire [`MEM_DATA_WIDTH-1:0] wdata;
  wire [3:0]                 wtag;

  wire [`MEM_ADDR_WIDTH-1:0] raddr;
  wire                       rsend;

  wire [`MEM_ADDR_WIDTH-1:0] radix_result_addr;
  wire                       search_surface_select;

  wire [`EQUIHASH_c-1:0] data_select;
  reg  [RADIX_BITS-1:0]  bucket_select, bucket_selectq;
  reg [3:0]             pass_rcnt;
  reg [3:0]             pass_wcnt;
  reg [2:0]             size_cnt;
  reg [`MEM_ADDR_WIDTH-1:0] read_cnt;
  reg [`MEM_ADDR_WIDTH-1:0] write_cnt;


  // Bucket Pointers
  reg [`MEM_ADDR_WIDTH-1:0] bucket0_cnt;
  reg [`MEM_ADDR_WIDTH-1:0] bucket1_cnt;
  reg [`MEM_ADDR_WIDTH-1:0] bucket2_cnt;
  reg [`MEM_ADDR_WIDTH-1:0] bucket3_cnt;
  reg [`MEM_ADDR_WIDTH-1:0] bucket4_cnt;
  reg [`MEM_ADDR_WIDTH-1:0] bucket5_cnt;
  reg [`MEM_ADDR_WIDTH-1:0] bucket6_cnt;
  reg [`MEM_ADDR_WIDTH-1:0] bucket7_cnt;
  reg [`MEM_ADDR_WIDTH-1:0] bucket8_cnt;
  reg [`MEM_ADDR_WIDTH-1:0] bucket9_cnt;
  reg [`MEM_ADDR_WIDTH-1:0] bucketA_cnt;
  reg [`MEM_ADDR_WIDTH-1:0] bucketB_cnt;
  reg [`MEM_ADDR_WIDTH-1:0] bucketC_cnt;
  reg [`MEM_ADDR_WIDTH-1:0] bucketD_cnt;
  reg [`MEM_ADDR_WIDTH-1:0] bucketE_cnt;
  reg [`MEM_ADDR_WIDTH-1:0] bucketF_cnt;

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

  assign search_surface_select = pass_rcnt[0];


  // Add flop stage between Data, Bucket &  to improve timing
  // Data Selection
  assign data_select = rdata[`EQUIHASH_c-1:0];
  // Bucket Selection
  always @(*)
  begin
    case(pass_wcnt)
      4'h0    : bucket_select = data_select[RADIX_BITS*1-1 : RADIX_BITS*0];
      4'h1    : bucket_select = data_select[RADIX_BITS*2-1 : RADIX_BITS*1];
      4'h2    : bucket_select = data_select[RADIX_BITS*3-1 : RADIX_BITS*2];
      4'h3    : bucket_select = data_select[RADIX_BITS*4-1 : RADIX_BITS*3];
      4'h4    : bucket_select = data_select[RADIX_BITS*5-1 : RADIX_BITS*4];
      4'h5    : bucket_select = {3'b000,data_select[20]};
      default : bucket_select = data_select[RADIX_BITS*2-1 : RADIX_BITS*1];
    endcase
  end

  // Write Address
  always @(posedge eclk)
  begin
    if (!rstb)
      waddr <= 32'h0;
    else
      case(bucket_select)
        4'h0    : waddr <= bucket0_cnt;
        4'h1    : waddr <= bucket1_cnt;
        4'h2    : waddr <= bucket2_cnt;
        4'h3    : waddr <= bucket3_cnt;
        4'h5    : waddr <= bucket5_cnt;
        4'h4    : waddr <= bucket4_cnt;
        4'h6    : waddr <= bucket6_cnt;
        4'h7    : waddr <= bucket7_cnt;
        4'h8    : waddr <= bucket8_cnt;
        4'h9    : waddr <= bucket9_cnt;
        4'hA    : waddr <= bucketA_cnt;
        4'hC    : waddr <= bucketC_cnt;
        4'hB    : waddr <= bucketB_cnt;
        4'hD    : waddr <= bucketD_cnt;
        4'hE    : waddr <= bucketE_cnt;
        4'hF    : waddr <= bucketF_cnt;
        default : waddr <= bucket0_cnt;
      endcase
  end

  // Read & Write State Machine
  reg [2:0] radix_rstate;
  reg [2:0] radix_rstate_next;

  reg pass_rcnt_rst;
  reg pass_rcnt_incr;

  reg read_cnt_rst;
  reg read_cnt_incr;

  reg [2:0] radix_wstate;
  reg [2:0] radix_wstate_next;

  reg pass_wcnt_rst;
  reg pass_wcnt_incr;

  reg write_cnt_rst;
  reg write_cnt_incr;

  reg snoop_rst;

  wire [3:0] snoop_pass;

  reg rvalid_go;
  reg rvalidq;
  reg [255:0] rdataq;

  always @(posedge eclk)
  begin
    if (!rstb)
      snoop_rst <= 1'b0;
    else
      snoop_rst <= (radix_start) || (radix_wstate==WSTATE_PASS_END1);
  end
  wire [`MEM_ADDR_WIDTH-1:0] read_end;

  assign read_end = ((search_surface_select) ? radix_scratch_addr : radix_base_addr) + radix_end;

  always @(posedge eclk)
  begin
    if (!rstb)
    begin
      radix_rstate <= 3'b0;
      radix_wstate <= 3'b0;
    end
    else
    begin
      radix_rstate <= radix_rstate_next;
      radix_wstate <= radix_wstate_next;
    end
  end

  always @(*)
  begin : radix_wfsm
    pass_wcnt_incr = 1'b0;
    pass_wcnt_rst = 1'b0;

    write_cnt_incr = 1'b0;
    write_cnt_rst = 1'b0;
    radix_done = 1'b0;
    rvalid_go = 1'b0;

    radix_wstate_next = WSTATE_IDLE;
    case (radix_wstate)
      WSTATE_IDLE:
      begin
        write_cnt_rst = 1'b1;
        pass_wcnt_rst = 1'b1;
        if (radix_start)
          radix_wstate_next = WSTATE_PASS;
      end
      WSTATE_PASS:
      begin
        if (rvalidq && !memc_cmd_full)
        begin
          write_cnt_incr = 1'b1;
          rvalid_go = 1'b1;
          radix_wstate_next = WSTATE_PASS;
        end
        else if ((write_cnt-32'h1)==radix_end)
        begin
          radix_wstate_next = WSTATE_PASS_END0;
        end
        else
          radix_wstate_next = WSTATE_PASS;
      end
      WSTATE_PASS_END0:
      begin
        if (!dcr_stall)
        begin
        radix_wstate_next = WSTATE_PASS_END1;
        pass_wcnt_incr = 1'b1;
        end
        else
          radix_wstate_next = WSTATE_PASS_END0;
      end
      WSTATE_PASS_END1:
      begin
        write_cnt_rst = 1'b1;
        if (pass_wcnt==RADIX_PASS)
          radix_wstate_next = WSTATE_DONE;
        else
          radix_wstate_next = WSTATE_PASS;
      end
      WSTATE_DONE:
      begin
        radix_done = 1'b1;
      end
    default: radix_wstate_next = WSTATE_IDLE;
    endcase
  end

  always @(*)
  begin : radix_rfsm
    pass_rcnt_rst = 1'b0;
    pass_rcnt_incr = 1'b0;

    read_cnt_rst = 1'b0;
    read_cnt_incr = 1'b0;

    radix_rstate_next = RSTATE_IDLE;

    case (radix_rstate)
      RSTATE_IDLE:
      begin
        pass_rcnt_rst = 1'b1;
        read_cnt_rst = 1'b1;

        if (radix_start)
          radix_rstate_next = RSTATE_PASS;

      end

      RSTATE_PASS:
      begin
        if ((read_cnt-32'h1)==read_end && !dcr_stall)
        begin
          read_cnt_incr = 1'b0;
          pass_rcnt_incr = 1'b1;
          radix_rstate_next = RSTATE_PASS_END;
        end
        else if (dcr_stall || memc_cmd_full || rvalidq)
        begin
          read_cnt_incr = 1'b0;
          radix_rstate_next = RSTATE_PASS;
        end
        else
        begin
          read_cnt_incr = 1'b1;
          radix_rstate_next = RSTATE_PASS;
        end
      end

      RSTATE_PASS_END:
      begin
        if (radix_wstate==WSTATE_PASS_END1)
        begin
          if (pass_rcnt==RADIX_PASS)
          begin
            radix_rstate_next = RSTATE_DONE;
          end
          else
          begin
            read_cnt_rst = 1'b1;
            radix_rstate_next = RSTATE_PASS;
          end
        end
        else
          radix_rstate_next = RSTATE_PASS_END;
      end
      RSTATE_DONE:
      begin
        read_cnt_rst = 1'b1;  //Wait until all reads have returned when ASYNC memory
        radix_rstate_next = RSTATE_IDLE;
      end
      default:
      begin
        radix_rstate_next = RSTATE_IDLE;
      end
    endcase // case (radix_rstate)
  end // radix_fsm

  always @(posedge eclk)
  begin
    if (!rstb)
    begin
      pass_rcnt <= 4'h0;
      pass_wcnt <= 4'h0;
      size_cnt <= 3'b0;
      read_cnt <=  `MEM_ADDR_WIDTH'h0;
      write_cnt <= `MEM_ADDR_WIDTH'h0;

      bucket0_cnt <= `MEM_ADDR_WIDTH'h0;
      bucket1_cnt <= `MEM_ADDR_WIDTH'h0;
      bucket2_cnt <= `MEM_ADDR_WIDTH'h0;
      bucket3_cnt <= `MEM_ADDR_WIDTH'h0;
      bucket4_cnt <= `MEM_ADDR_WIDTH'h0;
      bucket5_cnt <= `MEM_ADDR_WIDTH'h0;
      bucket6_cnt <= `MEM_ADDR_WIDTH'h0;
      bucket7_cnt <= `MEM_ADDR_WIDTH'h0;
      bucket8_cnt <= `MEM_ADDR_WIDTH'h0;
      bucket9_cnt <= `MEM_ADDR_WIDTH'h0;
      bucketA_cnt <= `MEM_ADDR_WIDTH'h0;
      bucketB_cnt <= `MEM_ADDR_WIDTH'h0;
      bucketC_cnt <= `MEM_ADDR_WIDTH'h0;
      bucketD_cnt <= `MEM_ADDR_WIDTH'h0;
      bucketE_cnt <= `MEM_ADDR_WIDTH'h0;
      bucketF_cnt <= `MEM_ADDR_WIDTH'h0;

      rvalidq <= 1'b0;
      rdataq <= 256'h0;
    end
    else
    begin
      //pass_rcnt
      if (pass_rcnt_rst)
        pass_rcnt <= 4'h0;
      else if (pass_rcnt_incr)
        pass_rcnt <= pass_rcnt + 4'h1;
      else
        pass_rcnt <= pass_rcnt;

      //pass_wcnt
      if (pass_wcnt_rst)
        pass_wcnt <= 4'h0;
      else if (pass_wcnt_incr)
        pass_wcnt <= pass_wcnt + 4'h1;
      else
        pass_wcnt <= pass_wcnt;

      //size_cnt
      if (rvalid)
        size_cnt <= (size_cnt==radix_size) ? 3'b000 : size_cnt + 3'b1;
      else
        size_cnt <= size_cnt;

      //read_cnt
      if (read_cnt_rst)
        read_cnt <= (search_surface_select) ? radix_scratch_addr : radix_base_addr;
      else if (read_cnt_incr)
        read_cnt <= read_cnt + 32'h1;
      else
        read_cnt <= read_cnt;

      //write_cnt
      if (write_cnt_rst)
        write_cnt <= 32'h0;
      else if (write_cnt_incr)
        write_cnt <= write_cnt + 32'h1;
      else
        write_cnt <= write_cnt;

      //bucket_cnt
      if (!rstb)
        bucket_selectq <= 4'h0;
      else
        bucket_selectq <= bucket_select;

      if (write_cnt_rst || !rstb)
      begin
        bucket0_cnt <= ((!search_surface_select) ? radix_scratch_addr : radix_base_addr) + bucket0_base;
        bucket1_cnt <= ((!search_surface_select) ? radix_scratch_addr : radix_base_addr) + bucket1_base;
        bucket2_cnt <= ((!search_surface_select) ? radix_scratch_addr : radix_base_addr) + bucket2_base;
        bucket3_cnt <= ((!search_surface_select) ? radix_scratch_addr : radix_base_addr) + bucket3_base;
        bucket4_cnt <= ((!search_surface_select) ? radix_scratch_addr : radix_base_addr) + bucket4_base;
        bucket5_cnt <= ((!search_surface_select) ? radix_scratch_addr : radix_base_addr) + bucket5_base;
        bucket6_cnt <= ((!search_surface_select) ? radix_scratch_addr : radix_base_addr) + bucket6_base;
        bucket7_cnt <= ((!search_surface_select) ? radix_scratch_addr : radix_base_addr) + bucket7_base;
        bucket8_cnt <= ((!search_surface_select) ? radix_scratch_addr : radix_base_addr) + bucket8_base;
        bucket9_cnt <= ((!search_surface_select) ? radix_scratch_addr : radix_base_addr) + bucket9_base;
        bucketA_cnt <= ((!search_surface_select) ? radix_scratch_addr : radix_base_addr) + bucketA_base;
        bucketB_cnt <= ((!search_surface_select) ? radix_scratch_addr : radix_base_addr) + bucketB_base;
        bucketC_cnt <= ((!search_surface_select) ? radix_scratch_addr : radix_base_addr) + bucketC_base;
        bucketD_cnt <= ((!search_surface_select) ? radix_scratch_addr : radix_base_addr) + bucketD_base;
        bucketE_cnt <= ((!search_surface_select) ? radix_scratch_addr : radix_base_addr) + bucketE_base;
        bucketF_cnt <= ((!search_surface_select) ? radix_scratch_addr : radix_base_addr) + bucketF_base;
      end
      else if (write_cnt_incr)
        case(bucket_selectq)
          4'h0   : begin bucket0_cnt <= bucket0_cnt + 32'h1;
                                                     bucket1_cnt <= bucket1_cnt; bucket2_cnt <= bucket2_cnt; bucket3_cnt <= bucket3_cnt;
                         bucket4_cnt <= bucket4_cnt; bucket5_cnt <= bucket5_cnt; bucket6_cnt <= bucket6_cnt; bucket7_cnt <= bucket7_cnt;
                         bucket8_cnt <= bucket8_cnt; bucket9_cnt <= bucket9_cnt; bucketA_cnt <= bucketA_cnt; bucketB_cnt <= bucketB_cnt;
                         bucketC_cnt <= bucketC_cnt; bucketD_cnt <= bucketD_cnt; bucketE_cnt <= bucketE_cnt; bucketF_cnt <= bucketF_cnt;
                   end
          4'h1   : begin bucket1_cnt <= bucket1_cnt + 32'h1;
                         bucket0_cnt <= bucket0_cnt;                             bucket2_cnt <= bucket2_cnt; bucket3_cnt <= bucket3_cnt;
                         bucket4_cnt <= bucket4_cnt; bucket5_cnt <= bucket5_cnt; bucket6_cnt <= bucket6_cnt; bucket7_cnt <= bucket7_cnt;
                         bucket8_cnt <= bucket8_cnt; bucket9_cnt <= bucket9_cnt; bucketA_cnt <= bucketA_cnt; bucketB_cnt <= bucketB_cnt;
                         bucketC_cnt <= bucketC_cnt; bucketD_cnt <= bucketD_cnt; bucketE_cnt <= bucketE_cnt; bucketF_cnt <= bucketF_cnt;
                   end
          4'h2   : begin bucket2_cnt <= bucket2_cnt + 32'h1;
                         bucket0_cnt <= bucket0_cnt; bucket1_cnt <= bucket1_cnt;                             bucket3_cnt <= bucket3_cnt;
                         bucket4_cnt <= bucket4_cnt; bucket5_cnt <= bucket5_cnt; bucket6_cnt <= bucket6_cnt; bucket7_cnt <= bucket7_cnt;
                         bucket8_cnt <= bucket8_cnt; bucket9_cnt <= bucket9_cnt; bucketA_cnt <= bucketA_cnt; bucketB_cnt <= bucketB_cnt;
                         bucketC_cnt <= bucketC_cnt; bucketD_cnt <= bucketD_cnt; bucketE_cnt <= bucketE_cnt; bucketF_cnt <= bucketF_cnt;
                   end
          4'h3   : begin bucket3_cnt <= bucket3_cnt + 32'h1;
                         bucket0_cnt <= bucket0_cnt; bucket1_cnt <= bucket1_cnt; bucket2_cnt <= bucket2_cnt;
                         bucket4_cnt <= bucket4_cnt; bucket5_cnt <= bucket5_cnt; bucket6_cnt <= bucket6_cnt; bucket7_cnt <= bucket7_cnt;
                         bucket8_cnt <= bucket8_cnt; bucket9_cnt <= bucket9_cnt; bucketA_cnt <= bucketA_cnt; bucketB_cnt <= bucketB_cnt;
                         bucketC_cnt <= bucketC_cnt; bucketD_cnt <= bucketD_cnt; bucketE_cnt <= bucketE_cnt; bucketF_cnt <= bucketF_cnt;
                   end
          4'h4   : begin bucket4_cnt <= bucket4_cnt + 32'h1;
                         bucket0_cnt <= bucket0_cnt; bucket1_cnt <= bucket1_cnt; bucket2_cnt <= bucket2_cnt; bucket3_cnt <= bucket3_cnt;
                                                     bucket5_cnt <= bucket5_cnt; bucket6_cnt <= bucket6_cnt; bucket7_cnt <= bucket7_cnt;
                         bucket8_cnt <= bucket8_cnt; bucket9_cnt <= bucket9_cnt; bucketA_cnt <= bucketA_cnt; bucketB_cnt <= bucketB_cnt;
                         bucketC_cnt <= bucketC_cnt; bucketD_cnt <= bucketD_cnt; bucketE_cnt <= bucketE_cnt; bucketF_cnt <= bucketF_cnt;
                   end
          4'h5   : begin bucket5_cnt <= bucket5_cnt + 32'h1;
                         bucket0_cnt <= bucket0_cnt; bucket1_cnt <= bucket1_cnt; bucket2_cnt <= bucket2_cnt; bucket3_cnt <= bucket3_cnt;
                         bucket4_cnt <= bucket4_cnt;                             bucket6_cnt <= bucket6_cnt; bucket7_cnt <= bucket7_cnt;
                         bucket8_cnt <= bucket8_cnt; bucket9_cnt <= bucket9_cnt; bucketA_cnt <= bucketA_cnt; bucketB_cnt <= bucketB_cnt;
                         bucketC_cnt <= bucketC_cnt; bucketD_cnt <= bucketD_cnt; bucketE_cnt <= bucketE_cnt; bucketF_cnt <= bucketF_cnt;
                   end
          4'h6   : begin bucket6_cnt <= bucket6_cnt + 32'h1;
                         bucket0_cnt <= bucket0_cnt; bucket1_cnt <= bucket1_cnt; bucket2_cnt <= bucket2_cnt; bucket3_cnt <= bucket3_cnt;
                         bucket4_cnt <= bucket4_cnt; bucket5_cnt <= bucket5_cnt;                             bucket7_cnt <= bucket7_cnt;
                         bucket8_cnt <= bucket8_cnt; bucket9_cnt <= bucket9_cnt; bucketA_cnt <= bucketA_cnt; bucketB_cnt <= bucketB_cnt;
                         bucketC_cnt <= bucketC_cnt; bucketD_cnt <= bucketD_cnt; bucketE_cnt <= bucketE_cnt; bucketF_cnt <= bucketF_cnt;
                   end
          4'h7   : begin bucket7_cnt <= bucket7_cnt + 32'h1;
                         bucket0_cnt <= bucket0_cnt; bucket1_cnt <= bucket1_cnt; bucket2_cnt <= bucket2_cnt; bucket3_cnt <= bucket3_cnt;
                         bucket4_cnt <= bucket4_cnt; bucket5_cnt <= bucket5_cnt; bucket6_cnt <= bucket6_cnt;
                         bucket8_cnt <= bucket8_cnt; bucket9_cnt <= bucket9_cnt; bucketA_cnt <= bucketA_cnt; bucketB_cnt <= bucketB_cnt;
                         bucketC_cnt <= bucketC_cnt; bucketD_cnt <= bucketD_cnt; bucketE_cnt <= bucketE_cnt; bucketF_cnt <= bucketF_cnt;
                   end
          4'h8   : begin bucket8_cnt <= bucket8_cnt + 32'h1;
                         bucket0_cnt <= bucket0_cnt; bucket1_cnt <= bucket1_cnt; bucket2_cnt <= bucket2_cnt; bucket3_cnt <= bucket3_cnt;
                         bucket4_cnt <= bucket4_cnt; bucket5_cnt <= bucket5_cnt; bucket6_cnt <= bucket6_cnt; bucket7_cnt <= bucket7_cnt;
                                                     bucket9_cnt <= bucket9_cnt; bucketA_cnt <= bucketA_cnt; bucketB_cnt <= bucketB_cnt;
                         bucketC_cnt <= bucketC_cnt; bucketD_cnt <= bucketD_cnt; bucketE_cnt <= bucketE_cnt; bucketF_cnt <= bucketF_cnt;
                   end
          4'h9   : begin bucket9_cnt <= bucket9_cnt + 32'h1;
                         bucket0_cnt <= bucket0_cnt; bucket1_cnt <= bucket1_cnt; bucket2_cnt <= bucket2_cnt; bucket3_cnt <= bucket3_cnt;
                         bucket4_cnt <= bucket4_cnt; bucket5_cnt <= bucket5_cnt; bucket6_cnt <= bucket6_cnt; bucket7_cnt <= bucket7_cnt;
                         bucket8_cnt <= bucket8_cnt;                             bucketA_cnt <= bucketA_cnt; bucketB_cnt <= bucketB_cnt;
                         bucketC_cnt <= bucketC_cnt; bucketD_cnt <= bucketD_cnt; bucketE_cnt <= bucketE_cnt; bucketF_cnt <= bucketF_cnt;
                   end
          4'hA   : begin bucketA_cnt <= bucketA_cnt + 32'h1;
                         bucket0_cnt <= bucket0_cnt; bucket1_cnt <= bucket1_cnt; bucket2_cnt <= bucket2_cnt; bucket3_cnt <= bucket3_cnt;
                         bucket4_cnt <= bucket4_cnt; bucket5_cnt <= bucket5_cnt; bucket6_cnt <= bucket6_cnt; bucket7_cnt <= bucket7_cnt;
                         bucket8_cnt <= bucket8_cnt; bucket9_cnt <= bucket9_cnt;                             bucketB_cnt <= bucketB_cnt;
                         bucketC_cnt <= bucketC_cnt; bucketD_cnt <= bucketD_cnt; bucketE_cnt <= bucketE_cnt; bucketF_cnt <= bucketF_cnt;
                   end
          4'hB   : begin bucketB_cnt <= bucketB_cnt + 32'h1;
                         bucket0_cnt <= bucket0_cnt; bucket1_cnt <= bucket1_cnt; bucket2_cnt <= bucket2_cnt; bucket3_cnt <= bucket3_cnt;
                         bucket4_cnt <= bucket4_cnt; bucket5_cnt <= bucket5_cnt; bucket6_cnt <= bucket6_cnt; bucket7_cnt <= bucket7_cnt;
                         bucket8_cnt <= bucket8_cnt; bucket9_cnt <= bucket9_cnt; bucketA_cnt <= bucketA_cnt;
                         bucketC_cnt <= bucketC_cnt; bucketD_cnt <= bucketD_cnt; bucketE_cnt <= bucketE_cnt; bucketF_cnt <= bucketF_cnt;
                   end
          4'hC   : begin bucketC_cnt <= bucketC_cnt + 32'h1;
                         bucket0_cnt <= bucket0_cnt; bucket1_cnt <= bucket1_cnt; bucket2_cnt <= bucket2_cnt; bucket3_cnt <= bucket3_cnt;
                         bucket4_cnt <= bucket4_cnt; bucket5_cnt <= bucket5_cnt; bucket6_cnt <= bucket6_cnt; bucket7_cnt <= bucket7_cnt;
                         bucket8_cnt <= bucket8_cnt; bucket9_cnt <= bucket9_cnt; bucketA_cnt <= bucketA_cnt; bucketB_cnt <= bucketB_cnt;
                                                     bucketD_cnt <= bucketD_cnt; bucketE_cnt <= bucketE_cnt; bucketF_cnt <= bucketF_cnt;
                   end
          4'hD   : begin bucketD_cnt <= bucketD_cnt + 32'h1;
                         bucket0_cnt <= bucket0_cnt; bucket1_cnt <= bucket1_cnt; bucket2_cnt <= bucket2_cnt; bucket3_cnt <= bucket3_cnt;
                         bucket4_cnt <= bucket4_cnt; bucket5_cnt <= bucket5_cnt; bucket6_cnt <= bucket6_cnt; bucket7_cnt <= bucket7_cnt;
                         bucket8_cnt <= bucket8_cnt; bucket9_cnt <= bucket9_cnt; bucketA_cnt <= bucketA_cnt; bucketB_cnt <= bucketB_cnt;
                         bucketC_cnt <= bucketC_cnt;                bucketE_cnt <= bucketE_cnt; bucketF_cnt <= bucketF_cnt;
                   end
          4'hE   : begin bucketE_cnt <= bucketE_cnt + 32'h1;
                         bucket0_cnt <= bucket0_cnt; bucket1_cnt <= bucket1_cnt; bucket2_cnt <= bucket2_cnt; bucket3_cnt <= bucket3_cnt;
                         bucket4_cnt <= bucket4_cnt; bucket5_cnt <= bucket5_cnt; bucket6_cnt <= bucket6_cnt; bucket7_cnt <= bucket7_cnt;
                         bucket8_cnt <= bucket8_cnt; bucket9_cnt <= bucket9_cnt; bucketA_cnt <= bucketA_cnt; bucketB_cnt <= bucketB_cnt;
                         bucketC_cnt <= bucketC_cnt; bucketD_cnt <= bucketD_cnt;                             bucketF_cnt <= bucketF_cnt;
                   end
          4'hF   : begin bucketF_cnt <= bucketF_cnt + 32'h1;
                         bucket0_cnt <= bucket0_cnt; bucket1_cnt <= bucket1_cnt; bucket2_cnt <= bucket2_cnt; bucket3_cnt <= bucket3_cnt;
                         bucket4_cnt <= bucket4_cnt; bucket5_cnt <= bucket5_cnt; bucket6_cnt <= bucket6_cnt; bucket7_cnt <= bucket7_cnt;
                         bucket8_cnt <= bucket8_cnt; bucket9_cnt <= bucket9_cnt; bucketA_cnt <= bucketA_cnt; bucketB_cnt <= bucketB_cnt;
                         bucketC_cnt <= bucketC_cnt; bucketD_cnt <= bucketD_cnt; bucketE_cnt <= bucketE_cnt;
                   end
        endcase
      else
      begin
        bucket0_cnt <= bucket0_cnt;
        bucket1_cnt <= bucket1_cnt;
        bucket2_cnt <= bucket2_cnt;
        bucket3_cnt <= bucket3_cnt;
        bucket4_cnt <= bucket4_cnt;
        bucket5_cnt <= bucket5_cnt;
        bucket6_cnt <= bucket6_cnt;
        bucket7_cnt <= bucket7_cnt;
        bucket8_cnt <= bucket8_cnt;
        bucket9_cnt <= bucket9_cnt;
        bucketA_cnt <= bucketA_cnt;
        bucketB_cnt <= bucketB_cnt;
        bucketC_cnt <= bucketC_cnt;
        bucketD_cnt <= bucketD_cnt;
        bucketE_cnt <= bucketE_cnt;
        bucketF_cnt <= bucketF_cnt;
      end
      if (rvalid)
        rdataq <= rdata;
      else
        rdataq <= rdataq;

      if (rvalid)
        rvalidq <= 1'b1;
      else if (rvalid_go)
        rvalidq <= 1'b0;
      else
        rvalidq <= rvalidq;
    end
  end

  //Output assigns
  assign raddr = read_cnt;
  assign rsend = read_cnt_incr;//(radix_rstate==RSTATE_PASS) && !dcr_stall && !memc_cmd_full;

  assign wdata = rdataq;
  assign wvalid = rvalid_go;
  assign wtag = 4'h2;

  assign radix_result_addr = (radix_done) ? ( (RADIX_PASS % 2 == 0) ? radix_base_addr : radix_scratch_addr )  : 32'h0;
  assign snoop_pass = pass_wcnt;
endmodule //collision_fetch
