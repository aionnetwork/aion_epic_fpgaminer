/* © Copyright ePIC Blockchain Technologies Inc. (2018).  All Rights Reserved.
 * Written by emai <emai@epicblockchain.io> June 2018
 */


/* "snoop" monitors the write data to pre-determine the bucket size and location
 * used in radix searching.  This allows for known bucket sizes thus removing
 * the need to dynamically allocate memory.
 *
 * The snoop is resetted after every pass of radix sorting hence values must be
 * sampled before this.  The 16-bucket configuration was chosen to meet timing
 * and complexity but larger RADIX_BITS other than 4 should be investigated
 * depending on the desired needs.
 */
`include "equihash_defines.v"

module snoop(
  input             eclk,
  input             rstb,

  input [3:0]       stage,
  input [3:0]       pass_cnt,
  input             pass_cnt0, //Set during blake2b & collision XOR writing
  input             bucket_cnt_rst,

  input             wvalid,
  input  [`MEM_DATA_WIDTH-1:0] wdata,

  output [`MEM_ADDR_WIDTH-1:0] bucket0_base,
  output [`MEM_ADDR_WIDTH-1:0] bucket1_base,
  output [`MEM_ADDR_WIDTH-1:0] bucket2_base,
  output [`MEM_ADDR_WIDTH-1:0] bucket3_base,
  output [`MEM_ADDR_WIDTH-1:0] bucket4_base,
  output [`MEM_ADDR_WIDTH-1:0] bucket5_base,
  output [`MEM_ADDR_WIDTH-1:0] bucket6_base,
  output [`MEM_ADDR_WIDTH-1:0] bucket7_base,
  output [`MEM_ADDR_WIDTH-1:0] bucket8_base,
  output [`MEM_ADDR_WIDTH-1:0] bucket9_base,
  output [`MEM_ADDR_WIDTH-1:0] bucketA_base,
  output [`MEM_ADDR_WIDTH-1:0] bucketB_base,
  output [`MEM_ADDR_WIDTH-1:0] bucketC_base,
  output [`MEM_ADDR_WIDTH-1:0] bucketD_base,
  output [`MEM_ADDR_WIDTH-1:0] bucketE_base,
  output [`MEM_ADDR_WIDTH-1:0] bucketF_base
  );


  parameter RADIX_BITS = 4; // Comparator size
  integer i;

  reg wvalidq;

  wire [3:0] next_pass_cnt;

  reg  [`MEM_ADDR_WIDTH-1:0] bucket [15:0];

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

  wire [`EQUIHASH_c-1:0] data_select;
  reg [RADIX_BITS-1:0]  bucket_select;

  assign next_pass_cnt = (pass_cnt0) ? 4'h0 : pass_cnt + 4'h1;

  assign data_select = wdata[`EQUIHASH_c-1:0];
  // Bucket Selection
  always @(posedge eclk)
  begin
  if (!rstb)
  begin
    bucket_select <= 4'h0;
  end
  begin
    case(next_pass_cnt)
      4'h0    : bucket_select <= data_select[RADIX_BITS*1-1 : RADIX_BITS*0];
      4'h1    : bucket_select <= data_select[RADIX_BITS*2-1 : RADIX_BITS*1];
      4'h2    : bucket_select <= data_select[RADIX_BITS*3-1 : RADIX_BITS*2];
      4'h3    : bucket_select <= data_select[RADIX_BITS*4-1 : RADIX_BITS*3];
      4'h4    : bucket_select <= data_select[RADIX_BITS*5-1 : RADIX_BITS*4];
      4'h5    : bucket_select <= {3'b000,data_select[20]};
      default : bucket_select <= data_select[RADIX_BITS*2-1 : RADIX_BITS*1];
    endcase
  end
  end

  always @(posedge eclk)
  begin
    if (!rstb)
    begin
      wvalidq <= 1'b0;
      for (i=0;i<16;i=i+1)
        bucket[i] <= `MEM_ADDR_WIDTH'h0;
    end
    else
    begin
      wvalidq <= wvalid;
      if (bucket_cnt_rst)
      begin
        for (i=0;i<16;i=i+1)
          bucket[i] <= `MEM_ADDR_WIDTH'h0;
      end
      else if (wvalidq)
      begin
        // Buckets 0 to 14
        for (i=0;i<16;i=i+1)
        begin
          if (i > bucket_select)
            bucket[i] <= bucket[i] + 32'h1;
          else
            bucket[i] <= bucket[i];
        end
      end
    end
  end

  //Output buckets
  assign bucket0_base = bucket[0];
  assign bucket1_base = bucket[1];
  assign bucket2_base = bucket[2];
  assign bucket3_base = bucket[3];
  assign bucket4_base = bucket[4];
  assign bucket5_base = bucket[5];
  assign bucket6_base = bucket[6];
  assign bucket7_base = bucket[7];
  assign bucket8_base = bucket[8];
  assign bucket9_base = bucket[9];
  assign bucketA_base = bucket[10];
  assign bucketB_base = bucket[11];
  assign bucketC_base = bucket[12];
  assign bucketD_base = bucket[13];
  assign bucketE_base = bucket[14];
  assign bucketF_base = bucket[15];

endmodule
