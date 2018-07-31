
#/* © Copyright ePIC Blockchain Technologies Inc. (2018).  All Rights Reserved.
# * Written by emai <emai@epicblockchain.io> June 2018
# */
CC = iverilog
LINT = verilator +1364-2001ext+ -Wall --lint-only --top-module blake2
TARGETS = radix_snoop.sim collision.sim blake2b.sim equihash.sim

SRC_DIR = ../rtl
TB_SRC_DIR = ../tb

all: $(TARGETS)

blake2b.sim: $(TB_SRC_DIR)/tb_blake2b.v $(SRC_DIR)/blake2b/blake2b.v $(SRC_DIR)/blake2b/blake2_core.v $(SRC_DIR)/blake2b/blake2_G.v $(SRC_DIR)/blake2b/blake2_m_select.v
		$(CC) -o $@ -I$(SRC_DIR) $^

radix_snoop.sim: $(TB_SRC_DIR)/tb_radix_snoop.v $(TB_SRC_DIR)/mem_ram_sync.v $(SRC_DIR)/radix/radix.v $(SRC_DIR)/radix/snoop.v $(SRC_DIR)/equihash_defines.v
	$(CC) -o $@ -I$(SRC_DIR) $^

collision.sim: $(TB_SRC_DIR)/tb_collision.v  $(TB_SRC_DIR)/mem_ram_sync.v $(SRC_DIR)/collision/collision.v $(SRC_DIR)/misc/ring_buffer.v $(SRC_DIR)/collision/collision_store.v $(SRC_DIR)/equihash_defines.v
		$(CC) -o $@ -I$(SRC_DIR) $^


equihash.sim: $(TB_SRC_DIR)/tb_equihash.v $(TB_SRC_DIR)/mem_ram_sync.v $(SRC_DIR)/radix/radix.v $(SRC_DIR)/radix/snoop.v $(SRC_DIR)/collision/collision.v $(SRC_DIR)/collision/collision_store.v \
	            $(SRC_DIR)/misc/ring_buffer.v $(SRC_DIR)/equihash_state/equihash_state.v $(SRC_DIR)/equihash_state/equihash_pointer.v $(SRC_DIR)/equihash.v \
	            $(SRC_DIR)/blake2b/blake2b.v $(SRC_DIR)/blake2b/blake2_core.v $(SRC_DIR)/blake2b/blake2_G.v $(SRC_DIR)/blake2b/blake2_m_select.v $(SRC_DIR)/misc/mem_gasket.v
			$(CC) -o $@ -I$(SRC_DIR) $^
lint:
	$(LINT) -I$(SRC_DIR)/*.v

clean:
	rm -f $(TARGETS)

help:
	@echo "Supported targets:"
	@echo "------------------"
	@echo "all:          Build all simulation targets."
	@echo "clean:        Remove build results."

.PHONY: all clean

#===================================================================
# EOF Makefile
#===================================================================
