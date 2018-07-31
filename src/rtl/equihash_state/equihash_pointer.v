/* © Copyright ePIC Blockchain Technologies Inc. (2018).  All Rights Reserved.
 * Written by emai <emai@epicblockchain.io> June 2018
 */

/* Stage0: blake2b writes to BUF0
 * StageX: radix reads from writes back to original location (Even[6] # of passes)
 *         collision reads from BUF[0/1] and writes to BUF[1/0] (returns size)
 *         binary search tree data is written to BUF2 (returns size)
 */

`include "equihash_defines.v"

module equihash_pointer(
                   input             eclk,
                   input             rstb,
                   input             mem_pointer_rst,

                   input [3:0]       stage,

                   //blake2b
                   output [`MEM_ADDR_WIDTH-1:0] blake2b_base_addr,

                   //radix
                   output [`MEM_ADDR_WIDTH-1:0] radix_base_addr,     //BUF0
                   output [`MEM_ADDR_WIDTH-1:0] radix_scratch_addr,  //BUF1
                   output [`MEM_ADDR_WIDTH-1:0] radix_end,           //Derivied from stage_nxor_end

                  // Collision
                   output [`MEM_ADDR_WIDTH-1:0] stage_cxor_base,     //BUF1
                   output [`MEM_ADDR_WIDTH-1:0] stage_cxor_end,      //Derived from stage_nxor_end + BUF1

                   output [`MEM_ADDR_WIDTH-1:0] stage_nxor_base,     //BUF0
                   input  [`MEM_ADDR_WIDTH-1:0] stage_nxor_end,      //Flopped at collision_done
                   output [`MEM_ADDR_WIDTH-1:0] stage_nxor_limit,    //

                   output [`MEM_ADDR_WIDTH-1:0] stage_pair_base,     //BUF2
                   input  [`MEM_ADDR_WIDTH-1:0] stage_pair_end,      //Flopped at collision_done

                   input collision_done

  );



  // 128MB Buffers, 0 & 1 are for data while 2 is for BST
  parameter MEM_BUF0 = 32'h00000000; // 512bit/256bit Address @ 0MB
`ifdef LOCAL_TESTBENCH
  parameter MEM_BUF1 = 32'h00000020; // 256bit Address @ 128MB
  parameter MEM_BUF2 = 32'h00000100; // 64bit aligned address @ 256MB
`else
  parameter MEM_BUF1 = 32'h00400000; // 512bit Address @ 256MB
  parameter MEM_BUF2 = 32'h02000000; // 64bit aligned address @ 512MB
`endif
  parameter MEM_START= 32'h00000000;
  parameter MEM_END  = 32'h01000000; // 512bit Address @ 1024MB

  // Output Signals
  wire [`MEM_ADDR_WIDTH-1:0] blake2b_base_addr;

  reg [`MEM_ADDR_WIDTH-1:0] radix_base_addr;
  reg [`MEM_ADDR_WIDTH-1:0] radix_scratch_addr;
  wire [`MEM_ADDR_WIDTH-1:0] radix_end;

  wire [`MEM_ADDR_WIDTH-1:0] stage_pair_base;

  reg [`MEM_ADDR_WIDTH-1:0] stage_cxor_base;
  wire [`MEM_ADDR_WIDTH-1:0] stage_cxor_end;

  reg [`MEM_ADDR_WIDTH-1:0] stage_nxor_base;
  wire [`MEM_ADDR_WIDTH-1:0] stage_nxor_limit;

  // Flopped
  reg [`MEM_ADDR_WIDTH-1:0] stage_nxor_endq;
  reg [`MEM_ADDR_WIDTH-1:0] stage_pair_endq;

  reg [3:0] stageq;
  wire stage_change;
  always @(posedge eclk)
  begin
    if (!rstb || mem_pointer_rst)
      stageq <= 4'h0;
    else
      stageq <= stage;
  end
  assign stage_change = (stage!=stageq);

// Current
always @(stage_change)
  begin
    //Radix
    case(stage)
      4'h1    : begin radix_base_addr = MEM_BUF0; radix_scratch_addr = MEM_BUF1; end
      4'h2    : begin radix_base_addr = MEM_BUF1; radix_scratch_addr = MEM_BUF0; end
      4'h3    : begin radix_base_addr = MEM_BUF0; radix_scratch_addr = MEM_BUF1; end
      4'h4    : begin radix_base_addr = MEM_BUF1; radix_scratch_addr = MEM_BUF0; end
      4'h5    : begin radix_base_addr = MEM_BUF0; radix_scratch_addr = MEM_BUF1; end
      4'h6    : begin radix_base_addr = MEM_BUF1; radix_scratch_addr = MEM_BUF0; end
      4'h7    : begin radix_base_addr = MEM_BUF0; radix_scratch_addr = MEM_BUF1; end
      4'h8    : begin radix_base_addr = MEM_BUF1; radix_scratch_addr = MEM_BUF0; end
      4'h9    : begin radix_base_addr = MEM_BUF0; radix_scratch_addr = MEM_BUF1; end
      default : begin radix_base_addr = MEM_BUF1; radix_scratch_addr = MEM_BUF0; end
    endcase
    //Collision
    case(stage)
      4'h1     : begin stage_cxor_base = MEM_BUF0; stage_nxor_base = MEM_BUF1; end
      4'h2     : begin stage_cxor_base = MEM_BUF1; stage_nxor_base = MEM_BUF0; end
      4'h3     : begin stage_cxor_base = MEM_BUF0; stage_nxor_base = MEM_BUF1; end
      4'h4     : begin stage_cxor_base = MEM_BUF1; stage_nxor_base = MEM_BUF0; end
      4'h5     : begin stage_cxor_base = MEM_BUF0; stage_nxor_base = MEM_BUF1; end
      4'h6     : begin stage_cxor_base = MEM_BUF1; stage_nxor_base = MEM_BUF0; end
      4'h7     : begin stage_cxor_base = MEM_BUF0; stage_nxor_base = MEM_BUF1; end
      4'h8     : begin stage_cxor_base = MEM_BUF1; stage_nxor_base = MEM_BUF0; end
      4'h9     : begin stage_cxor_base = MEM_BUF0; stage_nxor_base = MEM_BUF1; end
      default  : begin stage_cxor_base = 32'h0;  stage_nxor_base = 32'h0; end
    endcase
  end
 //stage_pair_end
 always @(posedge eclk)
 begin
   if (!rstb || mem_pointer_rst)
     stage_pair_endq <= MEM_BUF2;
   else if (collision_done)
     stage_pair_endq <= stage_pair_end;
   else
     stage_pair_endq <= stage_pair_endq;
 end
 // radix_end
 always @(posedge eclk)
 begin
   if (!rstb || mem_pointer_rst)
     stage_nxor_endq <= MEM_BUF1 - 32'h1;
  else if (collision_done)
    stage_nxor_endq <= stage_nxor_end - stage_nxor_base;
  else
    stage_nxor_endq <= stage_nxor_endq;
 end
 // Output Assignments
 assign blake2b_base_addr = MEM_BUF0;
 assign radix_end = stage_nxor_endq;
 assign stage_pair_base = stage_pair_endq;
 assign stage_cxor_end = (stage[0]) ? stage_nxor_endq + MEM_BUF0 : stage_nxor_endq + MEM_BUF1;
 assign stage_nxor_limit = (stage[0]) ? (MEM_BUF2>>2) : MEM_BUF1;
endmodule  //equihash_mem_pointer
