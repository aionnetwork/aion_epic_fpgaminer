// © Copyright ePIC Blockchain Technologies Inc. (2018).  All Rights Reserved.

`timescale 1ns/100ps

`include "equihash_defines.v"

module tb_collision();

  //----------------------------------------------------------------
  // Internal constant and parameter definitions.
  //----------------------------------------------------------------
  parameter DISPLAY_STATE = 1;

  parameter CLK_HALF_PERIOD = 5;
  parameter CLK_PERIOD = CLK_HALF_PERIOD*2;

  //----------------------------------------------------------------
  // Register and Wire declarations.
  //----------------------------------------------------------------
  reg [63 : 0]   cycle_ctr;
  reg [31 : 0]   error_ctr;
  reg [31 : 0]   tc_ctr;

  reg            tb_collision_start;
  reg            tb_collision_startq;
  wire           tb_collision_done;
  reg [3:0]      tb_stage;
  reg [31:0]     tb_stage_cxor_base;
  reg [31:0]     tb_stage_cxor_end;
  reg            tb_memc_cmd_full;

  reg            tb_clk;
  reg            tb_reset_n;

  reg            error_found;
  reg [31 : 0]   read_data;

  reg [511 : 0]  extracted_data;

  reg            display_cycle_ctr;
  reg            tb_fakesorted_init;
  reg [`MEM_ADDR_WIDTH-1:0]           tb_waddr;
  reg [`MEM_ADDR_WIDTH-1:0]           tb_waddrq;
  reg [`MEM_DATA_WIDTH-1:0]           tb_wdata;
  reg [`MEM_DATA_WIDTH-1:0]           tb_wdataq;
  reg                                 tb_wvalid;
  reg                                 tb_wvalidq;

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


  wire [`MEM_ADDR_WIDTH-1:0] raddr;
  wire                       rsend;
  wire                       rvalid;
  wire [`MEM_DATA_WIDTH-1:0] rdata;

  wire [`MEM_ADDR_WIDTH-1:0] waddr;
  wire [`MEM_DATA_WIDTH-1:0] wdata;
  wire                       wvalid;

  wire [3:0]                 snoop_pass;

  wire                       tb_uart_start;
  wire [63:0]                tb_uart_tdata;
  // The collision core
  collision collision (
    .eclk(tb_clk),
    .rstb(tb_reset_n),
    .stage(tb_stage),
    .memc_cmd_full(tb_memc_cmd_full),

    .collision_start(tb_collision_startq),
    .collision_done(tb_collision_done),

    // Read Port memory - XOR
    .raddr(raddr),
    .rtag(),
    .rsend(rsend),

    .rdata(rdata),
    .rvalid(rvalid),

    // Write Port Memory
    .waddr(waddr),
    .wdata(wdata),
    .wtag(),
    .wvalid(wvalid),

    .stage_pair_base({30'h30,2'b00}), // **64bit ADDRESS**
    .stage_pair_end(),

    .stage_cxor_base(tb_stage_cxor_base),
    .stage_cxor_end(tb_stage_cxor_end),

    .stage_nxor_base(32'h10),
    .stage_nxor_end(),
    .stage_nxor_limit(32'h20),

    .uart_start(tb_uart_start),
    .uart_tdata(tb_uart_tdata)

  );

  // The memory model
  mem_ram_sync mem_ram_sync(
      .clk(tb_clk),
      .rstn(tb_reset_n),
      .read_rq(rsend),
      .write_rq  (tb_fakesorted_init ? tb_wvalid : wvalid),
      .r_address(raddr[9:0]),
      .w_address(tb_fakesorted_init ? tb_waddr[9:0] : waddr[9:0]),
      .write_data(tb_fakesorted_init ? tb_wdata : wdata),
      .read_data(rdata),
      .read_valid(rvalid),
      .dump(tb_collision_startq || tb_collision_done )
  );

  //----------------------------------------------------------------
  // clk_gen
  //
  // Clock generator process.
  //----------------------------------------------------------------
  always
    begin : clk_gen
      #CLK_HALF_PERIOD tb_clk = !tb_clk;
    end // clk_gen


  //----------------------------------------------------------------
  // reset_dut
  //----------------------------------------------------------------
  task reset_dut;
    begin
      tb_reset_n = 0;
      #(10*CLK_PERIOD);
      tb_reset_n = 1;
      #(5*CLK_PERIOD);
    end
  endtask // reset_dut

  always @(posedge tb_clk)
  begin
    tb_collision_startq <= tb_collision_start;
    tb_wvalidq <= tb_wvalid;
    tb_waddrq <= tb_waddr;
    tb_wdataq <= tb_wdata;
  end

  //----------------------------------------------------------------
  // display_test_result()
  //
  // Display the accumulated test results.
  //----------------------------------------------------------------
  task display_test_result;
    begin
      if (error_ctr == 0)
        begin
          $display("*** All %02d test cases completed successfully", tc_ctr);
        end
      else
        begin
          $display("*** %02d test cases did not complete successfully.", error_ctr);
        end
    end
  endtask // display_test_result

  // mem_rand()
  integer i;
  task fakesorted;
    begin;
      tb_fakesorted_init = 1;
      for (i=0;i<16;i++)
        begin
          tb_wvalid = 1;
          tb_wdata = i/3 | (i<<224) | ((i/2)<<21) | (10'h3FF << 246);
          tb_waddr = i;
          //$display("Input %2d 0x%16x", i, tb_wdata) ;
          #(CLK_PERIOD);
        end
        #1
      tb_wvalid = 0;
      tb_fakesorted_init = 0;
    end
  endtask
  task fakebinary;
    begin;
      tb_fakesorted_init = 1;

      tb_wvalid = 1;
      tb_wdata = 256'h0000000000000000000000c0000000cbffc0000effc0000cffc0000dffc0000c;
      tb_waddr = 8'h33;
      #(CLK_PERIOD);

        #1
      tb_wvalid = 0;
      tb_fakesorted_init = 0;
    end
  endtask
  // radix_start()
  task radix_start;
    begin
      #CLK_PERIOD
      tb_collision_start = 1;
      #CLK_PERIOD
      tb_collision_start = 0;
    end
  endtask

  //----------------------------------------------------------------
  // init()
  //
  // Set the input to the DUT to defined values.
  //----------------------------------------------------------------
  task init;
    begin
      cycle_ctr  = 0;
      error_ctr  = 0;
      tc_ctr     = 0;
      tb_clk     = 1;
      tb_reset_n = 1;
      tb_collision_start = 0;

      tb_fakesorted_init = 1 ;
      tb_waddr = 0;
      tb_wdata = 0;
      tb_wvalid = 0;
    end
  endtask // init

  integer idx;
  initial
    begin
      $dumpfile("tb_collision.vcd");
      $dumpvars(0,tb_collision);
      for (idx = 0; idx < 4; idx = idx + 1)
        $dumpvars(0, tb_collision.collision.collision_store.data[idx]);
      $display("   -- Testbench for collision started --");
      init();
      reset_dut();
      fakesorted();
      tb_stage = 4'h0;
      tb_stage_cxor_base = 32'h0;
      tb_stage_cxor_end = 32'hF;
      radix_start();
      #(400*CLK_PERIOD);
      // Final Stage
      fakebinary();
      tb_stage = 4'h9;
      tb_stage_cxor_base = 32'h10;
      tb_stage_cxor_end = 32'h1E;
      radix_start();
      #(1000*CLK_PERIOD);
      display_test_result();
      $display("*** collision simulation done.");
      $finish_and_return(error_ctr);
    end
always @(posedge tb_clk)
  begin
    if (tb_uart_start)
      $display("Pairs [0x%6h,0x%6h]\n",tb_uart_tdata[53:32], tb_uart_tdata[21:0]);
  end
always @(posedge tb_clk)
begin
  cycle_ctr <= cycle_ctr + 64'h1;
  if (!tb_reset_n)
    tb_memc_cmd_full <= 1'b0;
  else if ((cycle_ctr[5:2]==4'b0))
    tb_memc_cmd_full <= 1'b1;
  else
    tb_memc_cmd_full <= 1'b0;
  end
endmodule
