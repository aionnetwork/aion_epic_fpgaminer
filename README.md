# EpicAionFPGAMiner

Algorithm: equihash (210,9)

Language: Verilog

Directories:

>src/rtl : Verilog of the design

>src/build : Makefile to build design simulation

>src/tb : Simple testbenches for design's major blocks

>src/fpga : FPGA build files

>doc/arch : Architecture related documentation

>doc/test : Testbench & Simulation related documentation

Referenced Code:

https://github.com/secworks/blake2
- Used for non pipelined blake2b with fixes for multimessage

https://github.com/progranism/Open-Source-FPGA-Bitcoin-Miner
- Used for UART RTL
