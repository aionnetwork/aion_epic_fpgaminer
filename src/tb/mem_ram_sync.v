module mem_ram_sync(
    clk,
    rstn,
    read_rq,
    write_rq,
    r_address,
    w_address,
    write_data,
    read_data,
    read_valid,
    dump
);
input           clk;
input           rstn;
input           read_rq;
input           write_rq;
input[9:0]      r_address;
input[9:0]      w_address;
input[255:0]     write_data;
output[255:0]    read_data;
output          read_valid;
input           dump;

reg[255:0]     read_data;
reg           read_valid;

integer out, i;

reg [255:0] memory_ram_d [1023:0];
reg [255:0] memory_ram_q [1023:0];

reg memory_error;

reg [255:0] read_data0,read_data1,read_data2,read_data3, read_data4, read_data5;
reg read_valid0, read_valid1,read_valid2, read_valid3,read_valid4, read_valid5;
// Use positive edge of clock to read the memory
// Implement cyclic shift right
always @(posedge clk )
begin
    if (!rstn)
    begin
        for (i=0;i<1024; i=i+1)
            memory_ram_q[i] <= 256'h0;//{$urandom,$urandom};
    end
    else
    begin
        for (i=0;i<1024; i=i+1)
             memory_ram_q[i] <= memory_ram_d[i];
    end
end


always @(*)
begin
    for (i=0;i<1024; i=i+1)
        memory_ram_d[i] = memory_ram_q[i];
    //if (write_rq && !read_rq)
    if (write_rq)
        memory_ram_d[w_address] = write_data;

end

always @(posedge clk)
begin
  //if (!write_rq && read_rq)
  if (read_rq)
    read_data0 <= memory_ram_q[r_address];
  read_data1 <= read_data0;
  read_data2 <= read_data1;
  read_data3 <= read_data2;
  read_data4 <= read_data3;
  read_data5 <= read_data4;
  read_data <= read_data5;

  read_valid0 <= read_rq;
  read_valid1 <= read_valid0;
  read_valid2 <= read_valid1;
  read_valid3 <= read_valid2;
  read_valid4 <= read_valid3;
  read_valid5 <= read_valid4;
  read_valid <= read_valid5;
end

always @(posedge clk)
begin
  if (!rstn)
    memory_error <= 1'b0;
  else
    memory_error <= memory_error | (read_rq && write_rq && (r_address==w_address));
end

always @(posedge clk)
begin
  if (dump)
  begin
    $display("----------------- MEMORY DUMP ---------------");
    for (i=0;i<16;i++)
      $display("%2d : 0x%16x 0x%16x 0x%16x 0x%16x",i,memory_ram_q[i],memory_ram_q[i+16],memory_ram_q[i+32],memory_ram_q[i+48]);
    for (i=64;i<80;i++)
      $display("%2d : 0x%16x 0x%16x",i,memory_ram_q[i],memory_ram_q[i+16]);
  end
end

endmodule
