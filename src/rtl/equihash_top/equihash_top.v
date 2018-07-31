/* © Copyright ePIC Blockchain Technologies Inc. (2018).  All Rights Reserved.
 * Written by emai <emai@epicblockchain.io> July 2018
 */

/* "equihash_top" block is used as the top level design for the FPGA.  It
 * contains a Xilinx MIG (memory controller) interface, UART communication
 * interface (Xilinx FIFO) and Xilinx XADC (temperature sensor).
 */

`timescale 1ps/1ps

module equihash_top #
  (

   //***************************************************************************
   // Traffic Gen related parameters
   //***************************************************************************
   parameter PORT_MODE             = "BI_MODE",
   parameter DATA_MODE             = 4'b0010,
   parameter TST_MEM_INSTR_MODE    = "R_W_INSTR_MODE",
   parameter EYE_TEST              = "FALSE",
                                     // set EYE_TEST = "TRUE" to probe memory
                                     // signals. Traffic Generator will only
                                     // write to one single location and no
                                     // read transactions will be generated.
   parameter DATA_PATTERN          = "DGEN_ALL",
                                      // For small devices, choose one only.
                                      // For large device, choose "DGEN_ALL"
                                      // "DGEN_HAMMER", "DGEN_WALKING1",
                                      // "DGEN_WALKING0","DGEN_ADDR","
                                      // "DGEN_NEIGHBOR","DGEN_PRBS","DGEN_ALL"
   parameter CMD_PATTERN           = "CGEN_ALL",
                                      // "CGEN_PRBS","CGEN_FIXED","CGEN_BRAM",
                                      // "CGEN_SEQUENTIAL", "CGEN_ALL"
   parameter CMD_WDT               = 'h3FF,
   parameter WR_WDT                = 'h1FFF,
   parameter RD_WDT                = 'h3FF,
   parameter SEL_VICTIM_LINE       = 0,
   parameter BEGIN_ADDRESS         = 32'h00000000,
   parameter END_ADDRESS           = 32'h00ffffff,
   parameter PRBS_EADDR_MASK_POS   = 32'hff000000,

   //***************************************************************************
   // The following parameters refer to width of various ports
   //***************************************************************************
   parameter CK_WIDTH              = 1,
                                     // # of CK/CK# outputs to memory.
   parameter nCS_PER_RANK          = 1,
                                     // # of unique CS outputs per rank for phy
   parameter CKE_WIDTH             = 1,
                                     // # of CKE outputs to memory.
   parameter DM_WIDTH              = 8,
                                     // # of DM (data mask)
   parameter ODT_WIDTH             = 1,
                                     // # of ODT outputs to memory.
   parameter BANK_WIDTH            = 3,
                                     // # of memory Bank Address bits.
   parameter COL_WIDTH             = 10,
                                     // # of memory Column Address bits.
   parameter CS_WIDTH              = 1,
                                     // # of unique CS outputs to memory.
   parameter DQ_WIDTH              = 64,
                                     // # of DQ (data)
   parameter DQS_WIDTH             = 8,
   parameter DQS_CNT_WIDTH         = 3,
                                     // = ceil(log2(DQS_WIDTH))
   parameter DRAM_WIDTH            = 8,
                                     // # of DQ per DQS
   parameter ECC                   = "OFF",
   parameter ECC_TEST              = "OFF",
   //parameter nBANK_MACHS           = 4,
   parameter nBANK_MACHS           = 4,
   parameter RANKS                 = 1,
                                     // # of Ranks.
   parameter ROW_WIDTH             = 14,
                                     // # of memory Row Address bits.
   parameter ADDR_WIDTH            = 28,
                                     // # = RANK_WIDTH + BANK_WIDTH
                                     //     + ROW_WIDTH + COL_WIDTH;
                                     // Chip Select is always tied to low for
                                     // single rank devices

   //***************************************************************************
   // The following parameters are mode register settings
   //***************************************************************************
   parameter BURST_MODE            = "8",
                                     // DDR3 SDRAM:
                                     // Burst Length (Mode Register 0).
                                     // # = "8", "4", "OTF".
                                     // DDR2 SDRAM:
                                     // Burst Length (Mode Register).
                                     // # = "8", "4".


   //***************************************************************************
   // The following parameters are multiplier and divisor factors for PLLE2.
   // Based on the selected design frequency these parameters vary.
   //***************************************************************************
   parameter CLKIN_PERIOD          = 5000,
                                     // Input Clock Period
   parameter CLKFBOUT_MULT         = 8,
                                     // write PLL VCO multiplier
   parameter DIVCLK_DIVIDE         = 1,
                                     // write PLL VCO divisor
   parameter CLKOUT0_PHASE         = 337.5,
                                     // Phase for PLL output clock (CLKOUT0)
   parameter CLKOUT0_DIVIDE        = 2,
                                     // VCO output divisor for PLL output clock (CLKOUT0)
   parameter CLKOUT1_DIVIDE        = 2,
                                     // VCO output divisor for PLL output clock (CLKOUT1)
   parameter CLKOUT2_DIVIDE        = 32,
                                     // VCO output divisor for PLL output clock (CLKOUT2)
   parameter CLKOUT3_DIVIDE        = 8,
                                     // VCO output divisor for PLL output clock (CLKOUT3)
   parameter MMCM_VCO              = 800,
                                     // Max Freq (MHz) of MMCM VCO
   parameter MMCM_MULT_F           = 4,
                                     // write MMCM VCO multiplier
   parameter MMCM_DIVCLK_DIVIDE    = 1,
                                     // write MMCM VCO divisor

   //***************************************************************************
   // Simulation parameters
   //***************************************************************************
   parameter SIMULATION            = "FALSE",
                                     // Should be TRUE during design simulations and
                                     // FALSE during implementations

   //***************************************************************************
   // IODELAY and PHY related parameters
   //***************************************************************************
   parameter TCQ                   = 100,

   parameter DRAM_TYPE             = "DDR3",


   //***************************************************************************
   // System clock frequency parameters
   //***************************************************************************
   parameter nCK_PER_CLK           = 4,
                                     // # of memory CKs per fabric CLK



   //***************************************************************************
   // Debug parameters
   //***************************************************************************
   parameter DEBUG_PORT            = "OFF",
                                     // # = "ON" Enable debug signals/controls.
                                     //   = "OFF" Disable debug signals/controls.

   parameter RST_ACT_LOW           = 1
                                     // =1 for active low reset,
                                     // =0 for active high.
   )
  (

   // Inouts
   inout [63:0]                         ddr3_dq,
   inout [7:0]                        ddr3_dqs_n,
   inout [7:0]                        ddr3_dqs_p,

   // Outputs
   output [13:0]                       ddr3_addr,
   output [2:0]                      ddr3_ba,
   output                                       ddr3_ras_n,
   output                                       ddr3_cas_n,
   output                                       ddr3_we_n,
   output                                       ddr3_reset_n,
   output [0:0]                        ddr3_ck_p,
   output [0:0]                        ddr3_ck_n,
   output [0:0]                       ddr3_cke,

   output [0:0]           ddr3_cs_n,

   output [7:0]                        ddr3_dm,

   output [0:0]                       ddr3_odt,


   // Inputs

   // Differential system clocks
   input                                        sys_clk_p,
   input                                        sys_clk_n,


   //output                                       tg_compare_error,
   //output                                       init_calib_complete,
   //input  [11:0]                                device_temp_i,
                      // The 12 MSB bits of the temperature sensor transfer
                      // function need to be connected to this port. This port
                      // will be synchronized w.r.t. to fabric clock internally.

   //UART
   input uart_rx,
   output uart_tx,

   // System reset - Default polarity of sys_rst pin is Active Low.
   // System reset polarity will change based on the option
   // selected in GUI.
   input                                        sys_rst
   );

function integer clogb2 (input integer size);
    begin
      size = size - 1;
      for (clogb2=1; size>1; clogb2=clogb2+1)
        size = size >> 1;
    end
  endfunction // clogb2

  function integer STR_TO_INT;
    input [7:0] in;
    begin
      if(in == "8")
        STR_TO_INT = 8;
      else if(in == "4")
        STR_TO_INT = 4;
      else
        STR_TO_INT = 0;
    end
  endfunction


  localparam DATA_WIDTH            = 64;
  localparam RANK_WIDTH = clogb2(RANKS);
  localparam PAYLOAD_WIDTH         = (ECC_TEST == "OFF") ? DATA_WIDTH : DQ_WIDTH;
  localparam BURST_LENGTH          = STR_TO_INT(BURST_MODE);
  localparam APP_DATA_WIDTH        = 2 * nCK_PER_CLK * PAYLOAD_WIDTH;
  localparam APP_MASK_WIDTH        = APP_DATA_WIDTH / 8;

  //***************************************************************************
  // Traffic Gen related parameters (derived)
  //***************************************************************************
  localparam  TG_ADDR_WIDTH = ((CS_WIDTH == 1) ? 0 : RANK_WIDTH)
                                 + BANK_WIDTH + ROW_WIDTH + COL_WIDTH;
  localparam MASK_SIZE             = DATA_WIDTH/8;


  // Wire declarations

  wire [(2*nCK_PER_CLK)-1:0]              app_ecc_multiple_err;
  wire [(2*nCK_PER_CLK)-1:0]              app_ecc_single_err;
  wire [ADDR_WIDTH-1:0]                 app_addr;
  wire [2:0]                            app_cmd;
  wire                                  app_en;
  wire                                  app_rdy;
  wire [APP_DATA_WIDTH-1:0]             app_rd_data;
  wire                                  app_rd_data_end;
  wire                                  app_rd_data_valid;
  wire [APP_DATA_WIDTH-1:0]             app_wdf_data;
  wire                                  app_wdf_end;
  wire [APP_MASK_WIDTH-1:0]             app_wdf_mask;
  wire                                  app_wdf_rdy;
  wire                                  app_sr_active;
  wire                                  app_ref_ack;
  wire                                  app_zq_ack;
  wire                                  app_wdf_wren;
  wire [(64+(2*APP_DATA_WIDTH))-1:0]      error_status;
  wire [(PAYLOAD_WIDTH/8)-1:0] cumlative_dq_lane_error;
  wire                                  mem_pattern_init_done;
  wire [47:0]                           tg_wr_data_counts;
  wire [47:0]                           tg_rd_data_counts;
  wire                                  modify_enable_sel;
  wire [2:0]                            data_mode_manual_sel;
  wire [2:0]                            addr_mode_manual_sel;
  wire [APP_DATA_WIDTH-1:0]             cmp_data;
  reg [63:0]                            cmp_data_r;
  wire                                  cmp_data_valid;
  reg                                   cmp_data_valid_r;
  wire                                  cmp_error;
  wire [(PAYLOAD_WIDTH/8)-1:0]            dq_error_bytelane_cmp;

  wire                                  clk;
  wire                                  rst;

  wire                                  dbg_sel_pi_incdec;
  wire                                  dbg_pi_f_inc;
  wire                                  dbg_pi_f_dec;
  wire                                  dbg_sel_po_incdec;
  wire                                  dbg_po_f_inc;
  wire                                  dbg_po_f_stg23_sel;
  wire                                  dbg_po_f_dec;


  wire                                  vio_modify_enable;
  wire [3:0]                            vio_data_mode_value;
  wire                                  vio_pause_traffic;
  wire [2:0]                            vio_addr_mode_value;
  wire [3:0]                            vio_instr_mode_value;
  wire [1:0]                            vio_bl_mode_value;
  wire [9:0]                            vio_fixed_bl_value;
  wire [2:0]                            vio_fixed_instr_value;
  wire                                  vio_data_mask_gen;
  wire                                  vio_tg_rst;
  wire                                  vio_dbg_sel_pi_incdec;
  wire                                  vio_dbg_pi_f_inc;
  wire                                  vio_dbg_pi_f_dec;
  wire                                  vio_dbg_sel_po_incdec;
  wire                                  vio_dbg_po_f_inc;
  wire                                  vio_dbg_po_f_stg23_sel;
  wire                                  vio_dbg_po_f_dec;

  wire [11:0]                           device_temp;


//***************************************************************************

  mig_7series_0 u_mig_7series_0
      (


// Memory interface ports
       .ddr3_addr                      (ddr3_addr),
       .ddr3_ba                        (ddr3_ba),
       .ddr3_cas_n                     (ddr3_cas_n),
       .ddr3_ck_n                      (ddr3_ck_n),
       .ddr3_ck_p                      (ddr3_ck_p),
       .ddr3_cke                       (ddr3_cke),
       .ddr3_ras_n                     (ddr3_ras_n),
       .ddr3_we_n                      (ddr3_we_n),
       .ddr3_dq                        (ddr3_dq),
       .ddr3_dqs_n                     (ddr3_dqs_n),
       .ddr3_dqs_p                     (ddr3_dqs_p),
       .ddr3_reset_n                   (ddr3_reset_n),
       .init_calib_complete            (init_calib_complete),

       .ddr3_cs_n                      (ddr3_cs_n),
       .ddr3_dm                        (ddr3_dm),
       .ddr3_odt                       (ddr3_odt),
// Application interface ports
       .app_addr                       (app_addr),
       .app_cmd                        (app_cmd),
       .app_en                         (app_en),
       .app_wdf_data                   (app_wdf_data),
       .app_wdf_end                    (app_wdf_end),
       .app_wdf_wren                   (app_wdf_wren),
       .app_rd_data                    (app_rd_data),
       .app_rd_data_end                (app_rd_data_end),
       .app_rd_data_valid              (app_rd_data_valid),
       .app_rdy                        (app_rdy),
       .app_wdf_rdy                    (app_wdf_rdy),
       .app_sr_req                     (1'b0),
       .app_ref_req                    (1'b0),
       .app_zq_req                     (1'b0),
       .app_sr_active                  (app_sr_active),
       .app_ref_ack                    (app_ref_ack),
       .app_zq_ack                     (app_zq_ack),
       .ui_clk                         (clk),
       .ui_clk_sync_rst                (rst),

       .app_wdf_mask                   (app_wdf_mask),


// System Clock Ports
       .sys_clk_p                       (sys_clk_p),
       .sys_clk_n                       (sys_clk_n),
       //.device_temp_i                  (12'b0),
       .device_temp            (device_temp),
       `ifdef SKIP_CALIB
       .calib_tap_req                    (calib_tap_req),
       .calib_tap_load                   (calib_tap_load),
       .calib_tap_addr                   (calib_tap_addr),
       .calib_tap_val                    (calib_tap_val),
       .calib_tap_load_done              (calib_tap_load_done),
       `endif

       .sys_rst                        (sys_rst)
       );


wire uart_tx, uart_rx, uart_start, uart_done;
wire [511:0] uart_tdata, uart_rdata;

reg [63:0] headernonce;
reg uart_startq, uart_startqq,uart_startqqq,uart_startqqqq;
reg [63:0] uart_tdataq,uart_tdataqq,uart_tdataqqq,uart_tdataqqqq;
wire uart_headernonce_send;
reg uart_headernonce_sendq;
wire solution_found;
reg [31:0] solution_data;

always @(posedge clk)
begin
  if (rst)
  begin
    headernonce <= {32'hDEADBEEF,32'h0ABCDEF0};
    uart_startq <= 1'b0;
    uart_startqq <= 1'b0;
    uart_startqqq <= 1'b0;
    uart_startqqqq <= 1'b0;

    uart_tdataq <= uart_tdata;
    uart_tdataqq <= uart_tdataq;
    uart_tdataqqq <= uart_tdataqq;
    uart_tdataqqqq <= uart_tdataqqq;

    uart_headernonce_sendq <= 1'b0;
  end
  else
  begin
    uart_startq <= uart_start;
    uart_startqq <= uart_startq;
    uart_startqqq <= uart_startqq;
    uart_startqqqq <= uart_startqqq;

    uart_tdataq <= uart_tdata[63:0];
    uart_tdataqq <= uart_tdataq;
    uart_tdataqqq <= uart_tdataqq;
    uart_tdataqqqq <= uart_tdataqqq;

    uart_headernonce_sendq <= uart_headernonce_send;
  end
end
always @(*)
begin
  if (uart_headernonce_send)
    solution_data = headernonce[63:32];
  else if (uart_headernonce_sendq)
    solution_data = headernonce[31:0];
  else if (uart_startqqq)
    solution_data = uart_tdataqqq[63:32];
  else
    solution_data = uart_tdataqqqq[31:0];
end
assign solution_found = uart_startqqq || uart_startqqqq|| uart_headernonce_send || uart_headernonce_sendq;

comm_uart comm_uart (
	.comm_clk(clk),
	.uart_rx(uart_rx),
	.uart_tx(uart_tx),

	.hash_clk(clk),
	.rx_new_golden_ticket(solution_found),
	.rx_golden_ticket(solution_data),

	.tx_new_work(uart_done),
	.tx_midstate(uart_rdata[255:0]),
	.tx_blockdata(uart_rdata[479:256])
	);

equihash equihash (
       .eclk(clk),
       .rstb(!rst),

       // UART RX/TX information
       .uart_done(uart_done),
       .uart_rdata(uart_rdata[479:0]),

       .uart_start(uart_start),
       .uart_tdata(uart_tdata[63:0]),
       .uart_headernonce_send(uart_headernonce_send),

       .memc_init_done       (init_calib_complete),
       .memc_cmd_full        (~app_rdy),
       .memc_cmd_en          (app_en),
       .memc_cmd_instr       (app_cmd),
       .memc_cmd_bl          (),
       .memc_cmd_addr        (app_addr),
       .memc_wr_en           (app_wdf_wren),
       .memc_wr_end          (app_wdf_end),
       .memc_wr_mask         (app_wdf_mask),
       .memc_wr_data         (app_wdf_data),
       .memc_wr_full         (~app_wdf_rdy),
       .memc_rd_en           (),
       .memc_rd_data         (app_rd_data),
       .memc_rd_empty        (~app_rd_data_valid)

 );

endmodule
