module ring_buffer #(parameter ADDR_W = 4, DATA_W = 256, BUFF_L = 16, ALMST_F = 3, ALMST_E = 3)
// buffer length must be less than or equal to address space as in  BUFF_L <or= 2^(ADDR_W)-1
			(
			output reg 		[DATA_W- 1	:	0]				data_out,
			output reg 		[ADDR_W		:	0]				  data_count,
			output	reg															empty,
			output	reg															full,
			output	reg															almst_empty,
			output	reg															almst_full,
			output	reg															err,
      output  reg   [ADDR_W -1 : 0]           wr_ptr,
      output  reg   [ADDR_W -1 : 0]           rd_ptr,
			input		wire	[DATA_W -1	:	0]				data_in,
			input		wire														wr_en,
			input		wire														rd_en,
			input		wire 														rstb,
			input		wire														eclk
			);


////--------------- internal variables ---------------------------------------------------------

			reg 				[DATA_W-1 : 0] 	mem_array [0 : (2**ADDR_W)-1];
			//reg					[ADDR_W-1 : 0]	rd_ptr, wr_ptr;
			reg					[ADDR_W-1 : 0]	rd_ptr_nxt, wr_ptr_nxt;
			reg														full_ff, empty_ff;
			reg														full_ff_nxt, empty_ff_nxt;
			reg														almst_f_ff, almst_e_ff;
			reg														almst_f_ff_nxt, almst_e_ff_nxt;
			reg					[ADDR_W : 0]		q_reg, q_nxt;
			reg														q_add, q_sub;
//// ------------------------------------------------------------------------------------------------


//// Always block to update the states
//// ------------------------------------------------------------------------------------------------
	always @ (posedge eclk)
		begin	:	reg_update
			if(rstb == 1'b 0)
				begin
					rd_ptr <= {(ADDR_W-1){1'b 0}};
					wr_ptr <= {(ADDR_W-1){1'b 0}};
					full_ff <= 1'b 0;
					empty_ff <= 1'b 1;
					almst_f_ff <= 1'b 0;
					almst_e_ff <= 1'b 1;
					q_reg <= {(ADDR_W){1'b 0}};
				end
			else
				begin
					rd_ptr <= rd_ptr_nxt;
					wr_ptr <= wr_ptr_nxt;
					full_ff <= full_ff_nxt;
					empty_ff <= empty_ff_nxt;
					almst_f_ff <= almst_f_ff_nxt;
					almst_e_ff <= almst_e_ff_nxt;
					q_reg <= q_nxt;
				 end
		end	// end of always


//// Control for almost full and almost emptly flags
//// ------------------------------------------------------------------------------------------------
	always @ ( almst_e_ff, almst_f_ff, q_reg)
		begin	:	Wtr_Mrk_Cont
			almst_e_ff_nxt = almst_e_ff;
			almst_f_ff_nxt = almst_f_ff;
		   //// check to see if wr_ptr is ALMST_E away from rd_ptr (aka almost empty)
			if(q_reg < ALMST_E)
				almst_e_ff_nxt = 1'b 1;
			else
				almst_e_ff_nxt = 1'b 0;

			if(q_reg > BUFF_L-ALMST_F)
				almst_f_ff_nxt = 1'b 1;
			else
				almst_f_ff_nxt = 1'b 0;

		end	// end of always

//// Control for read and write pointers and empty/full flip flops
	always @ (wr_en, rd_en, wr_ptr, rd_ptr, empty_ff, full_ff, q_reg)
		begin

			wr_ptr_nxt = wr_ptr ;											//// no change to pointers
			rd_ptr_nxt = rd_ptr;
			full_ff_nxt = full_ff;
			empty_ff_nxt = empty_ff;
			q_add = 1'b 0;
			q_sub = 1'b 0;
		////---------- check if fifo is full during a write attempt, after a write increment counter
		////----------------------------------------------------
			if(wr_en == 1'b 1 & rd_en == 1'b 0)
				begin
					if(full_ff == 1'b 0)
						begin
							if(wr_ptr < BUFF_L-1)
								begin
									q_add = 1'b 1;
									wr_ptr_nxt = wr_ptr + 1;
									empty_ff_nxt = 1'b 0;
								end
							else
								begin
									wr_ptr_nxt = {(ADDR_W-1){1'b 0}};
									empty_ff_nxt = 1'b 0;
								end
							//// check if fifo is full
							if( (wr_ptr+1 == rd_ptr) || ((wr_ptr == BUFF_L-1) && (rd_ptr == 1'b 0)))
								full_ff_nxt = 1'b 1;
						end
				end

		////---------- check to see if fifo is empty during a read attempt, after a read decrement counter
		////---------------------------------------------------------------
			if( (wr_en == 1'b 0) && (rd_en == 1'b 1))
				begin
					if(empty_ff == 1'b 0)
						begin
							if(rd_ptr < BUFF_L-1 )
								begin
									if(q_reg > 0)
										q_sub = 1'b 1;
									else
										q_sub = 1'b 0;
									rd_ptr_nxt = rd_ptr + 1;
									full_ff_nxt = 1'b 0;
								end
							else
								begin
									rd_ptr_nxt = {(ADDR_W-1){1'b 0}};
									full_ff_nxt = 1'b 0;
								end

							//// check if fifo is empty
							if( (rd_ptr  + 1 == wr_ptr) || ((rd_ptr == BUFF_L -1) && (wr_ptr == 1'b 0 )))
								empty_ff_nxt = 1'b 1;
						end
				end

		//// -----------------------------------------------------------------
			if( (wr_en == 1'b 1) && (rd_en == 1'b 1))
				begin
					if(wr_ptr < BUFF_L -1)
						wr_ptr_nxt = wr_ptr  + 1;
					else
						wr_ptr_nxt =  {(ADDR_W-1){1'b 0}};

					if(rd_ptr < BUFF_L -1)
						rd_ptr_nxt = rd_ptr + 1;
					else
						rd_ptr_nxt = {(ADDR_W-1){1'b 0}};
				end

		end  // end of always


//// Control for memory array writing and reading
//// ----------------------------------------------------------------------
	always @ (posedge eclk)
		begin		:		mem_cont
			if( rstb == 1'b 0)
				begin
					mem_array[rd_ptr] <=  {(DATA_W-1){1'b 0}};
					data_out <= {(DATA_W-1){1'b 0}};
					err <= 1'b 0;
				end
			else
				begin
					////  if write enable and not full then latch in data and increment wright pointer
					if( (wr_en == 1'b 1) && (full_ff == 1'b 0) )
						begin
							mem_array[wr_ptr] <=  data_in;
							err <= 1'b 0;
						end
					else if( (wr_en == 1'b 1) && (full_ff == 1'b 1))      ////  check if full and trying to write
						err <= 1'b 1;

					//// if read enable and fifo not empty then latch data out and increment read pointer
					if( (rd_en == 1'b 1) && (empty_ff == 1'b 0))
						begin
							data_out <= mem_array[rd_ptr];
							err <= 1'b 0;
						end
					else if( (rd_en == 1'b 1) && (empty_ff == 1'b 1))
						err <= 1'b 1;

				end	// end else
		end	// end always


//// Combo Counter with Control Flags
//// ------------------------------------------------------------------------------------------------
	always @ ( q_sub, q_add, q_reg)
		begin	:	Counter
			case( {q_sub , q_add} )
				2'b 01 :
						q_nxt = q_reg + 1;
				2'b 10 :
						q_nxt = q_reg - 1;
				default :
						q_nxt = q_reg;
			endcase
		end	// end of always

//// Connect internal regs to ouput ports
//// ------------------------------------------------------------------------------------------------
	always @ (full_ff, empty_ff, almst_e_ff, almst_f_ff, q_reg)
		begin
			full = full_ff;
			empty = empty_ff;
			almst_empty = almst_e_ff;
			almst_full = almst_f_ff;
			data_count = q_reg;
		end

endmodule
