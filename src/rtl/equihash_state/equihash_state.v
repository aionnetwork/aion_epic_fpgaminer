/* © Copyright ePIC Blockchain Technologies Inc. (2018).  All Rights Reserved.
 * Written by emai <emai@epicblockchain.io> June 2018
 */

/* "equihash_state" block controls the flow of the algoritm providing 'go'
 * signals to the blake2b, radix and collision blocks.  The main stage counter
 * resides here and is controlled by the equihash state machine (equihash_fsm).
 */

`include "equihash_defines.v"

module equihash_state(
                   input             eclk,
                   input             rstb,

                   input             init_done,

                   output [3:0]      stage,
                   output [2:0]      state,

                   input             uart_done,

                   output            blake2b_start,
                   input             blake2b_done,

                   output            radix_start,
                   input             radix_done,

                   output            collision_start,
                   input             collision_done,

                   output            snoop_pass_cnt0,

                   //blake2b
                   output [`MEM_ADDR_WIDTH-1:0] blake2b_base_addr,

                   //radix
                   output [`MEM_ADDR_WIDTH-1:0] radix_base_addr,
                   output [`MEM_ADDR_WIDTH-1:0] radix_scratch_addr,
                   output [`MEM_ADDR_WIDTH-1:0] radix_end,

                   // Collision
                   output [`MEM_ADDR_WIDTH-1:0] stage_cxor_base,
                   output [`MEM_ADDR_WIDTH-1:0] stage_cxor_end,

                   output [`MEM_ADDR_WIDTH-1:0] stage_nxor_base,
                   input  [`MEM_ADDR_WIDTH-1:0] stage_nxor_end,
                   output [`MEM_ADDR_WIDTH-1:0] stage_nxor_limit,

                   output [`MEM_ADDR_WIDTH-1:0] stage_pair_base,
                   input  [`MEM_ADDR_WIDTH-1:0] stage_pair_end,

                   output equihash_state_done


                  );

  //----------------------------------------------------------------
  // Output registers & wires
  //----------------------------------------------------------------
  reg blake2b_start, blake2b_go;
  reg radix_start, radix_go;
  reg collision_start, collision_go;
  reg mem_pointer_rst;
  reg equihash_state_done, equihash_state_done_valid;

  wire [3:0] stage;
  wire [2:0] state;
  wire       snoop_pass_cnt0;

  //----------------------------------------------------------------
  // Configuration parameters.
  //----------------------------------------------------------------
  parameter NUM_ROUNDS = `EQUIHASH_k;

  localparam STATE_IDLE      = 3'h0;
  localparam STATE_BLAKE2B   = 3'h1;
  localparam STATE_RADIX     = 3'h2;
  localparam STATE_COLLISION = 3'h3;
  localparam STATE_DONE      = 3'h4;


//----------------------------------------------------------------
// stg_ctr
// Update logic for the round counter, a monotonically
// increasing counter with reset.
//----------------------------------------------------------------

reg [3 : 0] stg_ctr;
reg [3 : 0] stg_ctr_next;
reg         stg_ctr_inc;
reg         stg_ctr_rst;

  always @ (posedge eclk or negedge rstb)
  begin : reg_update
    if (!rstb)
      begin
        stg_ctr <= 0;
      end
    else
      begin
        if (stg_ctr_rst)
          stg_ctr <= 4'h0;
        else if (stg_ctr_inc)
          stg_ctr <= stg_ctr + 4'h1;
        else
          stg_ctr <= stg_ctr;
      end
  end

  reg [2 : 0] equihash_state;
  reg [2 : 0] equihash_state_next;

  always @(posedge eclk)
  begin
    if (!rstb)
      equihash_state <= 3'b0;
    else
      equihash_state <= equihash_state_next;
  end

  always @*
    begin : equihash_fsm

      stg_ctr_inc         = 1'b0;
      stg_ctr_rst         = 1'b0;

      blake2b_go          = 1'b0;
      radix_go            = 1'b0;
      collision_go        = 1'b0;
      mem_pointer_rst     = 1'b0;
      equihash_state_done_valid = 1'b0;

      equihash_state_next = equihash_state;

      case (equihash_state)
        STATE_IDLE:
          begin
            mem_pointer_rst = 1'b1;
            if (uart_done && init_done)
              begin
                equihash_state_next = STATE_BLAKE2B;
                blake2b_go = 1'b1;
              end
            else
              begin
                stg_ctr_rst = 1'b1;
              end
          end
        STATE_BLAKE2B:
          begin
            if (blake2b_done)
              begin
                equihash_state_next = STATE_RADIX;
                stg_ctr_inc = 1'b1;
                radix_go = 1'b1;
              end
          end
        STATE_RADIX:
          begin
            if (radix_done)
              begin
                equihash_state_next = STATE_COLLISION;
                collision_go = 1'b1;
              end
            end
          STATE_COLLISION:
          begin
            if (collision_done)
              begin
                if (stg_ctr==`EQUIHASH_k)
                  begin
                    equihash_state_next = STATE_DONE;
                  end
                else if (stage_nxor_end==stage_nxor_base) //early termination
                  equihash_state_next = STATE_DONE;
                else
                  begin
                    equihash_state_next = STATE_RADIX;
                    radix_go = 1'b1;
                    stg_ctr_inc = 1'b1;
                  end
              end
          end
        STATE_DONE:
          begin
            stg_ctr_rst = 1'b1;
            equihash_state_done_valid = 1'b1;
            equihash_state_next = STATE_IDLE;
          end
        default:
          begin
            equihash_state_next = STATE_IDLE;
          end
      endcase // case (equihash_state)
    end // equihash_fsm

  always @(posedge eclk)
  begin
    if (!rstb)
    begin
      blake2b_start <= 1'b0;
      radix_start <= 1'b0;
      collision_start <= 1'b0;
      equihash_state_done <= 1'b0;
    end
    else
    begin
      if (blake2b_go)
        blake2b_start <= 1'b1;
      else
        blake2b_start <= 1'b0;

      if (radix_go)
        radix_start <= 1'b1;
      else
        radix_start <= 1'b0;

      if (collision_go)
        collision_start <= 1'b1;
      else
        collision_start <= 1'b0;

      if (equihash_state_done_valid)
        equihash_state_done <= 1'b1;
      else
        equihash_state_done <= 1'b0;
    end
  end
  equihash_pointer equihash_pointer(
    .eclk(eclk),
    .rstb(rstb),
    .mem_pointer_rst(mem_pointer_rst),

    .stage(stage),

    .blake2b_base_addr (blake2b_base_addr),

    .radix_base_addr   (radix_base_addr),
    .radix_scratch_addr(radix_scratch_addr),
    .radix_end         (radix_end),

    .stage_pair_base   (stage_pair_base),
    .stage_pair_end    (stage_pair_end),

    .stage_cxor_base   (stage_cxor_base),
    .stage_cxor_end    (stage_cxor_end),

    .stage_nxor_base   (stage_nxor_base),
    .stage_nxor_end    (stage_nxor_end),
    .stage_nxor_limit  (stage_nxor_limit),

    .collision_done    (collision_done)

  );

  // outputs
  assign stage = stg_ctr;
  assign state = equihash_state;
  assign snoop_pass_cnt0 = (equihash_state==STATE_BLAKE2B) || (equihash_state==STATE_COLLISION);

endmodule //main_stage
