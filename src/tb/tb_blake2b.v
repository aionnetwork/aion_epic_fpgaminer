// © Copyright ePIC Blockchain Technologies Inc. (2018).  All Rights Reserved.

//------------------------------------------------------------------
// Simulator directives.
//------------------------------------------------------------------
`timescale 1ns/100ps

module tb_blake2b();

  //----------------------------------------------------------------
  // Internal constant and parameter definitions.
  //----------------------------------------------------------------
  parameter DISPLAY_STATE = 1;

  parameter CLK_HALF_PERIOD = 2;
  parameter CLK_PERIOD      = 2 * CLK_HALF_PERIOD;


  //----------------------------------------------------------------
  // Register and Wire declarations.
  //----------------------------------------------------------------
  reg [63 : 0]   cycle_ctr;
  reg [31 : 0]   error_ctr;
  reg [31 : 0]   tc_ctr;

  reg            tb_clk;
  reg            tb_reset_n;

  reg            tb_memc_cmd_full;
  reg            tb_blake2b_start;
  wire           tb_blake2b_done;
  reg            tb_uart_done;
  reg [479:0]    tb_uart_rdata;

  wire [255:0]   tb_wdata;
  wire [3:0]     tb_wtag;
  wire [31:0]    tb_waddr;
  wire           tb_wvalid;

  reg            error_found;
  reg [31 : 0]   read_data;

  reg [511 : 0]  extracted_data;

  reg            display_cycle_ctr;


  //----------------------------------------------------------------
  // blake2b devices under test.
  //----------------------------------------------------------------

  blake2b #(.NUM_INDEX(21'h7) ) blake2b (
    .eclk(tb_clk),
    .rstb(tb_reset_n),
    .memc_cmd_full(tb_memc_cmd_full),
    .blake2b_start(tb_blake2b_start),
    .blake2b_done(tb_blake2b_done),
    .blake2b_base_addr(32'h5A000000),
    .uart_done(tb_uart_done),
    .uart_rdata(tb_uart_rdata),
    .wdata(tb_wdata),
    .wtag(tb_wtag),
    .waddr(tb_waddr),
    .wvalid(tb_wvalid)
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
      #(2 * CLK_PERIOD);
      tb_reset_n = 1;
    end
  endtask // reset_dut


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
      tb_clk     = 0;
      tb_reset_n = 1;
    end
  endtask // init


  //----------------------------------------------------------------
  // test_512_core
  //
  // Test the 512-bit hashing core
  //----------------------------------------------------------------
  task test_blake2b_core(
      input [479 : 0]  block,
      input [511 : 0]  expected
    );
    begin
      tb_uart_rdata = block;

      reset_dut();

      tb_uart_done = 1;
      #(2 * CLK_PERIOD);
      tb_uart_done = 0;
      tb_blake2b_start = 1;
      #(2 * CLK_PERIOD);
      tb_blake2b_start = 0;

      while (!tb_blake2b_done)
        #(CLK_PERIOD);
      #(CLK_PERIOD);
      /*
      if (tb_digest_512 == expected)
        tc_ctr = tc_ctr + 1;
      else
        begin
          error_ctr = error_ctr + 1;
          $display("Failed test:");
          $display("block[1023:0768] = 0x%032x", block[1023:0768]);
          $display("block[0767:0512] = 0x%032x", block[0767:0512]);
          $display("block[0511:0256] = 0x%032x", block[0511:0256]);
          $display("block[0255:0000] = 0x%032x", block[0255:0000]);
          $display("tb_digest_512 = 0x%064x", tb_digest_512);
          $display("expected      = 0x%064x", expected);
          $display("");
        end */
    end
  endtask // test_512_core


  //----------------------------------------------------------------
  // blake2b
  //
  // The main test functionality.
  //----------------------------------------------------------------
  initial
    begin : blake2b_test
      $dumpfile("tb_blake2b.vcd");
      $dumpvars(0,tb_blake2b);
      $display("   -- Testbench for blake2b started --");
      init();

      test_blake2b_core(
        480'h0,
        512'h865939e120e6805438478841afb739ae4250cf372653078a065cdcfffca4caf798e6d462b65d658fc165782640eded70963449ae1500fb0f24981d7727e22c41
      );

      display_test_result();
      $display("*** blake2b simulation done.");
      $finish_and_return(error_ctr);
    end // blake2b_test
    always @(posedge tb_clk)
    begin
      if (tb_wvalid)
      begin
        $display("Index: 0x%6x 0x%8x 0x%52x",tb_wdata[245:224],tb_waddr,tb_wdata[209:0]);
      end
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
endmodule // tb_blake2b

//======================================================================
// EOF tb_blake2_core.v
//======================================================================
