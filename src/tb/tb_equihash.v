// © Copyright ePIC Blockchain Technologies Inc. (2018).  All Rights Reserved.

`timescale 1ns/100ps

`include "equihash_defines.v"

`define LOCAL_TESTBENCH
`define NO_PERSONALIZATION
module tb_equihash();

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

  reg            tb_clk;
  reg            tb_reset_n;

  reg            error_found;
  reg [31 : 0]   read_data;
  reg            dump;

  reg [511 : 0]  extracted_data;

  reg            display_cycle_ctr;

  reg            tb_fakesorted_init;

  reg [`MEM_ADDR_WIDTH-1:0]           tb_waddr;
  reg [`MEM_ADDR_WIDTH-1:0]           tb_waddrq;
  reg [`MEM_DATA_WIDTH-1:0]           tb_wdata;
  reg [`MEM_DATA_WIDTH-1:0]           tb_wdataq;
  reg                                 tb_wvalid;
  reg                                 tb_wvalidq;

  wire                       tb_uart_start;
  wire [63:0]                tb_uart_tdata;

  reg                        tb_uart_done;
  reg  [479:0]               tb_uart_rdata;

  reg                        tb_uart_doneq;
  reg  [479:0]               tb_uart_rdataq;

  reg                        radix_dump;

  wire                       tb_equihash_state_done;

  reg                        tb_memc_cmd_full;
  wire                       memc_cmd_en;
  wire [2:0]                 memc_cmd_instr;
  wire [5:0]                 memc_cmd_bl;
  wire [27:0]                memc_cmd_addr;

  wire                       memc_wr_en;
  wire                       memc_wr_end;
  wire [63:0]                memc_wr_mask;
  wire [511:0]               memc_wr_data;

  wire                       memc_rd_en;
  wire [511:0]               memc_rd_data;
  wire                       memc_rd_empty;
  // The equihash core
  equihash equihash (
    .eclk(tb_clk),
    .rstb(tb_reset_n),

    // UART RX/TX information
    .uart_done(tb_uart_doneq),
    .uart_rdata(tb_uart_rdataq),

    .uart_start(tb_uart_start),
    .uart_tdata(tb_uart_tdata),
    .uart_headernonce_send(),

    .memc_init_done(1'b1),

    .memc_cmd_full(tb_memc_cmd_full),
    .memc_cmd_en(memc_cmd_en),
    .memc_cmd_instr(memc_cmd_instr), //0 write, 1 read
    .memc_cmd_bl(memc_cmd_bl), //unused
    .memc_cmd_addr(memc_cmd_addr),

    .memc_wr_en(memc_wr_en),
    .memc_wr_end(memc_wr_end),

    .memc_wr_mask(memc_wr_mask),
    .memc_wr_data(memc_wr_data),
    .memc_wr_full(1'b0),

    .memc_rd_en(memc_rd_en),
    .memc_rd_data(memc_rd_data),
    .memc_rd_empty(!memc_rd_empty),

    .equihash_state_done(tb_equihash_state_done)
  );

  reg [255:0] memc_wr_dataq;
  always @(posedge tb_clk)
  begin
    if (!tb_reset_n)
      memc_wr_dataq <= 256'h0;
    else
      memc_wr_dataq <= memc_wr_data[255:0];
  end
  // The memory model
  mem_ram_sync mem_ram_sync(
      .clk(tb_clk),
      .rstn(tb_reset_n),
      .read_rq     ( memc_cmd_instr[0] && memc_cmd_en),
      .write_rq    (!memc_cmd_instr[0] && memc_cmd_en),
      .r_address   (memc_cmd_addr[12:3]),
      .w_address   (memc_cmd_addr[12:3]),
      .write_data  (memc_wr_data[255:0]),
      .read_data   (memc_rd_data[255:0]),
      .read_valid  (memc_rd_empty),
      .dump(tb_equihash.equihash.blake2b_done || tb_equihash.equihash.radix_done || tb_equihash.equihash.collision_done || tb_equihash_state_done) // || radix_dump)
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
    tb_uart_doneq <= tb_uart_done;
    tb_uart_rdataq <= tb_uart_rdata;
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
  task uart_done;
    begin
      #CLK_PERIOD
      tb_uart_done = 1;
      tb_uart_rdata = 480'h0;
      #CLK_PERIOD
      tb_uart_done = 0;
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
      tb_uart_done = 0;
      tb_fakesorted_init = 1 ;
      tb_waddr = 0;
      tb_wdata = 0;
      tb_wvalid = 0;
    end
  endtask // init

  integer idx;
  initial
    begin
      $dumpfile("tb_equihash.vcd");
      $dumpvars(0,tb_equihash);
      for (idx = 0; idx < 4; idx = idx + 1)
        $dumpvars(0, tb_equihash.equihash.collision.collision_store.data[idx]);
      $display("   -- Testbench for equihash started --");
      init();
      reset_dut();
      uart_done();
      #(26000*CLK_PERIOD);
      //Use tb_equihash_state_done
      display_test_result();
      $display("*** equihash simulation done.");
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
  radix_dump <= tb_equihash.equihash.radix.pass_wcnt_incr;
  if (!tb_reset_n)
    tb_memc_cmd_full <= 1'b0;
  else if ((cycle_ctr[4:2]==3'b0))
    tb_memc_cmd_full <= 1'b1;
  else
    tb_memc_cmd_full <= 1'b0;
end
endmodule
