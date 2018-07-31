/* © Copyright ePIC Blockchain Technologies Inc. (2018).  All Rights Reserved.
 * Written by emai <emai@epicblockchain.io> June 2018
 */

/* "blake2b" block generates the initial data set used in the Equihash
 * algorithm. This implementation uses the PERSONALIZATION feature of blake2b
 * and generates 2 indice worth of data every hash.  The blake2b read and write
 * state machines (blake2b_rfsm & blake2b_wfsm) control the hash core and
 * writing of data into memory.
 */

`include "equihash_defines.v"

module blake2b (
  input                        eclk,
  input                        rstb,

  input                        memc_cmd_full,

  input                        blake2b_start,
  output                       blake2b_done,

  input [`MEM_ADDR_WIDTH-1:0]  blake2b_base_addr,

  input                        uart_done,
  input [479:0]                uart_rdata,

  //Write Port

  output [`MEM_ADDR_WIDTH-1:0] waddr,
  output [3:0]                 wtag,
  output [`MEM_DATA_WIDTH-1:0] wdata,
  output                       wvalid

  );

  parameter [20:0] NUM_INDEX = 21'h1FFFFF;


  localparam BSTATE_IDLE      = 3'h0;
  localparam BSTATE_PASS0     = 3'h1;
  localparam BSTATE_WAIT0     = 3'h2;
  //localparam BSTATE_PASS1     = 3'h3;
  //localparam BSTATE_WAIT1     = 3'h4;
  localparam BSTATE_PASS_END  = 3'h3;
  localparam BSTATE_DONE      = 3'h4;

  localparam BWSTATE_IDLE     = 3'h0;
  localparam BWSTATE_0        = 3'h1;
  localparam BWSTATE_1        = 3'h2;
  localparam BWSTATE_DONE     = 3'h3;

  reg blake2b_done;
  reg [480:0] blake2b_data0;

  reg [`EQUIHASH_c-1:0] index_cnt; //21bits
  reg [`EQUIHASH_c  :0] write0_cnt, write1_cnt; //22bits
  reg                   index_cnt_incr;
  reg                   index_cnt_rst;

  reg [2:0] blake2b_state;
  reg [2:0] blake2b_state_next;

  reg blake2b_init;
  reg blake2b_next;
  reg blake2b_final_block;
  reg [511:0] blake2b_block;
  reg [127:0] blake2b_data_length;

  wire [511:0] blake2b_digest;
  wire blake2b_digest_valid;
  wire blake2b_ready;

  always @(posedge eclk)
  begin
    if (!rstb)
      blake2b_data0 <= 480'h0;
    else if (uart_done)
      blake2b_data0 <= uart_rdata;
    else
      blake2b_data0 <= blake2b_data0;
  end

  always @(posedge eclk)
  begin
    if (!rstb)
    begin
      blake2b_state <= 3'b0;
    end
    else
    begin
      blake2b_state <= blake2b_state_next;
    end
  end

  always @(*)
  begin : blake2b_rfsm

    index_cnt_rst = 1'b0;
    index_cnt_incr = 1'b0;

    blake2b_init = 1'b0;
    blake2b_next = 1'b0;
    blake2b_final_block = 1'b1;
    blake2b_data_length = 128'h80;

    blake2b_done = 1'b0;

    blake2b_state_next = BSTATE_IDLE;

    case (blake2b_state)
      BSTATE_IDLE:
      begin
        index_cnt_rst = 1'b1;

        if (blake2b_start)
          blake2b_state_next = BSTATE_PASS0;

      end
      BSTATE_PASS0:
      begin
        blake2b_init = 1'b1;
        blake2b_block = {blake2b_data0,index_cnt};
        blake2b_state_next = BSTATE_WAIT0;
      end
      BSTATE_WAIT0:
      begin
        if (blake2b_ready)
        begin
          if (index_cnt==NUM_INDEX)
            blake2b_state_next = BSTATE_PASS_END;
          else
          begin
            index_cnt_incr = 1'b1;
            blake2b_state_next = BSTATE_PASS0;
          end
        end
        else
          blake2b_state_next = BSTATE_WAIT0;
      end
      BSTATE_PASS_END:
      begin
          if (!wvalid && (bwstate==BWSTATE_IDLE))
            blake2b_state_next = BSTATE_DONE;
          else
            blake2b_state_next = BSTATE_PASS_END;
      end
      BSTATE_DONE:
      begin
        index_cnt_rst = 1'b1;
        blake2b_done = 1'b1;
        blake2b_state_next = BSTATE_IDLE;
      end
      default:
      begin
        blake2b_state_next = BSTATE_IDLE;
      end
    endcase // case (blake2b_state)
  end // blake2b_fsm

  always @(posedge eclk)
  begin
    if (!rstb)
    begin
      index_cnt <= 21'h0;
      write0_cnt <= 22'h0;
      write1_cnt <= 22'h1;
    end
    else
    begin
      if (index_cnt_rst)
      begin
        index_cnt <=  21'h0;
        write0_cnt <= 22'h0;
        write1_cnt <= 22'h1;
      end
      else if (index_cnt_incr)
      begin
        index_cnt <= index_cnt + 21'h1;
        write0_cnt <= write0_cnt + 22'h2;
        write1_cnt <= write1_cnt + 22'h2;
      end
      else
      begin
        index_cnt <= index_cnt;
        write0_cnt <= write0_cnt;
        write1_cnt <= write1_cnt;
      end
    end
  end

  // The BLAKE2b-512 core
   //DIGEST_LENGTH = 64
   //PERSONALIZATION = "AION0PoW"+210+9 // 0x41494f4e30506f57D209
  blake2_core #(.DIGEST_LENGTH(64)
  `ifndef NO_PERSONALIZATION
                ,.PERSONALIZATION({48'h0,80'h41494f4e30506f57D209})
  `endif
               ) blake2_core (
    .clk(eclk),
    .reset_n(rstb),
    .init(blake2b_init),
    .next(blake2b_next),
    .final_block(blake2b_final_block),
    .block({512'h0,blake2b_block}),
    .data_length(blake2b_data_length),
    .ready(blake2b_ready),
    .digest(blake2b_digest),
    .digest_valid(blake2b_digest_valid)
  );

  // Output assignments
  wire dvalid;
  wire [511:0] digest;
  wire [`MEM_DATA_WIDTH-1:0] wdata;
  reg  [`MEM_DATA_WIDTH-1:0] wdata0, wdata1;

  wire [`MEM_ADDR_WIDTH-1:0] waddr;
  reg  [`MEM_ADDR_WIDTH-1:0] waddr0, waddr1;
  wire [3:0]                 wtag;
  wire wvalid;

  reg wvalidq, wvalidqq;
  reg [1:0] bwstate, bwstate_next;
  always @(*)
  begin
    wvalidq = 1'b0;
    wvalidqq = 1'b0;
    bwstate_next = BWSTATE_IDLE;

    case (bwstate)
      BWSTATE_IDLE:
      begin
        if (blake2b_digest_valid) bwstate_next = BWSTATE_0;
      end
      BWSTATE_0:
      begin
        if (!memc_cmd_full)
        begin
          wvalidq = 1'b1;
          bwstate_next = BWSTATE_1;
        end
        else
          bwstate_next = BWSTATE_0;
      end
      BWSTATE_1:
      begin
        if (!memc_cmd_full)
        begin
          wvalidqq = 1'b1;
          bwstate_next = BWSTATE_IDLE;
        end
      else
        bwstate_next = BWSTATE_1;
      end
      default : bwstate_next = BWSTATE_IDLE;
    endcase
  end
  always @(posedge eclk)
  begin
    if (!rstb)
      bwstate <= BWSTATE_IDLE;
    else
      bwstate <= bwstate_next;
  end
  always @(posedge eclk)
  begin
    if (!rstb)
    begin
      wdata0 <= 256'h0;
      wdata1 <= 256'h0;
      waddr0 <= 32'h0;
      waddr1 <= 32'h0;
    end
    else if (blake2b_digest_valid && (blake2b_state==BSTATE_WAIT0))
    begin
      // Equihash typically splits the digest in 2 but Aion does 209:0 and 425:216
      // Indice are kept track in write0_cnt & write1_cnt
      wdata0 <= {10'h3FF,write0_cnt,14'b0,blake2b_digest[209:0]};
      wdata1 <= {10'h3FF,write1_cnt,14'b0,blake2b_digest[425:216]};
      waddr0 <= blake2b_base_addr + {10'h0,write0_cnt};
      waddr1 <= blake2b_base_addr + {10'h0,write1_cnt};
    end
    else
    begin
      wdata0 <= wdata0;
      wdata1 <= wdata1;
    end
  end
  assign wvalid = wvalidq || wvalidqq;
  `ifdef LOCAL_TESTBENCH
  assign wdata = ((wvalidqq) ? wdata1 : wdata0) | {193'h0,21'h1FFFF0,21'h1FFFF0,21'h1FFFF0};
  `else
  assign wdata = (wvalidqq) ? wdata1 : wdata0;
  `endif
  assign wtag = 4'h1;
  assign waddr = (wvalidqq) ? waddr1 : waddr0;

`ifdef LOCAL_TESTBENCH
  always @(posedge eclk)
  begin
    if (blake2b_digest_valid && (blake2b_state == BSTATE_WAIT0))
    begin
      $display("0x%128x",blake2b_digest);
    end
  end
`endif

endmodule//blake2b
