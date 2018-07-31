// © Copyright ePIC Blockchain Technologies Inc. (2018).  All Rights Reserved.

`timescale 1ns/100ps

`include "equihash_defines.v"

module tb_radix_snoop();

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

  reg            tb_radix_start;
  reg            tb_radix_startq;
  reg            tb_memc_cmd_full;

  reg            tb_clk;
  reg            tb_reset_n;

  reg            error_found;
  reg [31 : 0]   read_data;

  reg [511 : 0]  extracted_data;

  reg            display_cycle_ctr;
  reg            tb_fake2b_init;
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

  // The snoop core
  snoop snoop (
    .eclk(tb_clk),
    .rstb(tb_reset_n),
    .stage(4'h0),
    .pass_cnt(snoop_pass),
    .pass_cnt0(tb_fake2b_init),
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

    .wvalid(tb_fake2b_init ? tb_wvalidq : wvalid),
    .wdata(tb_fake2b_init ? tb_wdataq : wdata)
    );

  // The radix core
  radix radix (
    .eclk(tb_clk),
    .rstb(tb_reset_n),
    .stage(4'h0),
    .memc_cmd_full(tb_memc_cmd_full),

    .radix_start(tb_radix_startq),

    .radix_done(radix_done),
    .radix_result_addr(),

    // Data Pointers
    .radix_base_addr   (32'h00000000),
    .radix_scratch_addr(32'h00000020),
    .radix_end         (32'h0000001F),
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

    .snoop_rst(snoop_rst),
    .snoop_pass(snoop_pass)
    );

  // The memory model
  mem_ram_sync mem_ram_sync(
      .clk(tb_clk),
      .rstn(tb_reset_n),
      .read_rq(rsend),
      .write_rq  (tb_fake2b_init ? tb_wvalid : wvalid),
      .r_address(raddr[9:0]),
      .w_address(tb_fake2b_init ? tb_waddr[9:0] : waddr[9:0]),
      .write_data(tb_fake2b_init ? tb_wdata : wdata),
      .read_data(rdata),
      .read_valid(rvalid),
      .dump(snoop_rst)
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
    tb_radix_startq <= tb_radix_start;
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
          $display("*** All  %02d test cases completed successfully", tc_ctr);
        end
      else
        begin
          $display("*** %02d test cases did not complete successfully.", error_ctr);
        end
    end
  endtask // display_test_result

  // mem_rand()
  integer i;
  task fake2b;
    begin;
      tb_fake2b_init = 1;
      for (i=0;i<32;i++)
        begin
          tb_wvalid = 1;
          tb_wdata = {$urandom,$urandom} & 64'h1FFFFF | i << 248; // 21bit random data with 8bit index
          //i | (15-i << 4) | (i << 8) | (15-i << 12); ;//{$urandom,$urandom};//  | 64'hF;
          tb_waddr = i;
          //$display("Input %2d 0x%16x", i, tb_wdata) ;
          #(CLK_PERIOD);
        end
        #1
      tb_wvalid = 0;
      tb_fake2b_init = 0;
    end
  endtask
  // radix_start()
  task radix_start;
    begin
      #CLK_PERIOD
      tb_radix_start = 1;
      #CLK_PERIOD
      tb_radix_start = 0;
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
      tb_radix_start = 0;

      tb_fake2b_init = 1 ;
      tb_waddr = 0;
      tb_wdata = 0;
      tb_wvalid = 0;
    end
  endtask // init

  initial
    begin
      $dumpfile("tb_radix_snoop.vcd");
      $dumpvars(0,tb_radix_snoop);
      $display("   -- Testbench for radix & snoop started --");
      init();
      reset_dut();
      fake2b();
      radix_start();
      #(3000*CLK_PERIOD);
      display_test_result();
      $display("*** radix_snoop simulation done.");
      $finish_and_return(error_ctr);
    end
    always @(posedge tb_clk)
    begin
      cycle_ctr <= cycle_ctr + 64'h1;
      if (!tb_reset_n)
        tb_memc_cmd_full <= 1'b0;
      else if (cycle_ctr[5:2]==4'b0)
        tb_memc_cmd_full <= 1'b1;
      else
        tb_memc_cmd_full <= 1'b0;
    end
endmodule
