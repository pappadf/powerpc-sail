# powerpc-sail — build system
#
# Usage:
#   make check          typecheck the model (fast, no code generation)
#   make emulator       build the C emulator  -> build/ppc_<core>
#   make run            build and run the embedded smoke test
#   make test           assemble test/*.S and diff emulator output against
#                       the matching test/*.expected  (needs a powerpc
#                       cross toolchain: apt install gcc-powerpc-linux-gnu)
#   make test-disasm    run those programs with -v 0x1, which exercises the
#                       disassembler on every instruction they execute
#   make check-assembly every instruction has an `assembly` clause (run by
#                       `make check`; Sail itself does not check this)
#
#   make clean
#
# Core selection: the model is a set of common files plus one core
# directory implementing the core interface (model/ppc_core_iface.sail).
#   make CORE=p601      (default; future: CORE=p603, CORE=p604)
#
# FILE ORDER MATTERS: Sail requires declaration before use, and the
# scattered instruction/SPR definitions are opened in ppc_insts_begin.sail /
# ppc_sprs.sail and closed in ppc_insts_end.sail — every file contributing
# clauses must sit between them.  Core files are interleaved at the marked
# points.

SAIL ?= sail
# Deferred (`=`, not `:=`): asking Sail where its runtime lives is only needed
# to link the emulator, so targets that never link — `clean` above all — must
# not shell out to a compiler that may not be installed.  Everything derived
# from these has to stay deferred too, or the expansion happens here anyway.
SAIL_DIR = $(shell $(SAIL) --dir)
SAIL_LIB_DIR = $(SAIL_DIR)/lib

CORE ?= p601
MODEL := model
CORE_DIR := $(MODEL)/cores/$(CORE)

# Core-specific instruction files (must come before ppc_insts_end.sail).
ifeq ($(CORE),p601)
CORE_EXTRA_INSTS := $(CORE_DIR)/p601_insts_power.sail
CORE_EXTRA_ASSEMBLY := $(CORE_DIR)/p601_assembly.sail
endif

# --- Ordered source list -----------------------------------------------------
SAIL_SRCS := \
	$(MODEL)/prelude.sail \
	$(MODEL)/ppc_types.sail \
	$(MODEL)/ppc_core_iface.sail \
	$(MODEL)/ppc_regs.sail \
	$(CORE_DIR)/$(CORE)_regs.sail \
	$(MODEL)/ppc_debug.sail \
	$(MODEL)/ppc_harness.sail \
	$(MODEL)/ppc_softfloat.sail \
	$(MODEL)/ppc_mem.sail \
	$(MODEL)/ppc_mmu.sail \
	$(CORE_DIR)/$(CORE)_mmu.sail \
	$(MODEL)/ppc_exceptions.sail \
	$(MODEL)/ppc_sprs.sail \
	$(CORE_DIR)/$(CORE)_sprs.sail \
	$(MODEL)/ppc_insts_begin.sail \
	$(MODEL)/ppc_insts_int.sail \
	$(MODEL)/ppc_insts_loadstore.sail \
	$(MODEL)/ppc_insts_branch.sail \
	$(MODEL)/ppc_insts_fp.sail \
	$(MODEL)/ppc_insts_system.sail \
	$(MODEL)/ppc_insts_cache.sail \
	$(CORE_EXTRA_INSTS) \
	$(MODEL)/ppc_assembly.sail \
	$(CORE_EXTRA_ASSEMBLY) \
	$(MODEL)/ppc_insts_end.sail \
	$(CORE_DIR)/$(CORE)_core.sail \
	$(MODEL)/ppc_step.sail \
	$(MODEL)/main.sail

BUILD := build
EMULATOR := $(BUILD)/ppc_$(CORE)

C_DIR := c

CC ?= gcc
# -include harness_hooks.h: Sail emits calls to an `extern` val but no
# declaration for it, so without this the generated code calls the hooks
# implicitly-declared and gcc warns (and, in principle, could get the ABI
# wrong).  Forcing the header in front of every translation unit is the
# smallest fix and costs nothing.
C_FLAGS = -O2 -I $(SAIL_LIB_DIR) -I $(C_DIR) -include $(C_DIR)/harness_hooks.h
C_LIBS := -lgmp -lz
# sail_failure.c provides sail_match_failure, which the generated code calls
# when a mapping has no clause for a value — the `assembly` mapping's failure
# mode for an instruction nobody wrote a disassembly clause for.
C_SRCS = $(SAIL_LIB_DIR)/sail.c $(SAIL_LIB_DIR)/rts.c $(SAIL_LIB_DIR)/elf.c \
         $(SAIL_LIB_DIR)/sail_failure.c

# --- Test programs -----------------------------------------------------------
# Each test/<name>.S is assembled and linked at a fixed address (test/link.ld),
# run under the emulator, and its halt line + final state dump compared with
# test/<name>.expected.  Model banner, boot line and instruction trace are cut
# so that expected files stay independent of them.
#
# Programs are loaded as flat binaries (-b <addr>,<file>) with the entry point
# supplied separately (-n): the Sail C runtime's ELF loader accepts only ARM,
# RISC-V and x86 objects, so the model's ELF path (-e, elf_entry()) cannot be
# used for PowerPC until that is fixed upstream.
#
# Output is captured from the first [halt] or [checkstop] line onwards: those
# are the two ways run() can end, and everything before them (banner, boot
# line, instruction trace) is deliberately excluded so expected files do not
# depend on it.

TEST_DIR := test
TEST_CC ?= powerpc-linux-gnu-gcc
TEST_OBJCOPY ?= powerpc-linux-gnu-objcopy
TEST_READELF ?= powerpc-linux-gnu-readelf
TEST_LD_FLAGS := -nostdlib -nostartfiles -static -Wl,--build-id=none \
                 -Wl,-T,$(TEST_DIR)/link.ld
# Must match the base address in test/link.ld.
TEST_LOAD_ADDR ?= 0x00001000
TEST_STEP_LIMIT ?= 100000

TEST_SRCS := $(sort $(wildcard $(TEST_DIR)/*.S))
TEST_ELFS := $(patsubst $(TEST_DIR)/%.S,$(BUILD)/$(TEST_DIR)/%.elf,$(TEST_SRCS))
TEST_BINS := $(TEST_ELFS:.elf=.bin)

.PHONY: all check check-assembly emulator run test test-elfs test-disasm test-accept \
        harness harness-cov harness-test clean
.PRECIOUS: $(BUILD)/$(TEST_DIR)/%.elf $(BUILD)/$(TEST_DIR)/%.bin

all: check

check: $(SAIL_SRCS)
	$(SAIL) $(SAIL_SRCS)
	@$(MAKE) -s check-assembly

# Sail does not require a scattered mapping to cover every constructor, so a
# missing `assembly` clause is invisible until the -v 0x1 trace hits it and
# the emulator dies of a match failure.  Compare the two lists instead: every
# `union clause ast` must have exactly one `mapping clause assembly`.
check-assembly:
	@mkdir -p $(BUILD)
	@grep -h '^union clause ast' $(SAIL_SRCS) \
	  | sed 's/union clause ast = *//; s/ *:.*//' | sort -u > $(BUILD)/ast-names
	@grep -h '^mapping clause assembly' $(SAIL_SRCS) \
	  | sed 's/mapping clause assembly = *//; s/[( ].*//' | sort -u > $(BUILD)/asm-names
	@missing=`comm -23 $(BUILD)/ast-names $(BUILD)/asm-names`; \
	 extra=`comm -13 $(BUILD)/ast-names $(BUILD)/asm-names`; \
	 if [ -n "$$missing" ]; then \
	   echo "no assembly clause for:"; echo "$$missing"; exit 1; fi; \
	 if [ -n "$$extra" ]; then \
	   echo "assembly clause for unknown instruction:"; echo "$$extra"; exit 1; fi; \
	 echo "assembly: `wc -l < $(BUILD)/ast-names | tr -d ' '` instructions, all with a clause" 

$(BUILD)/model.c: $(SAIL_SRCS)
	mkdir -p $(BUILD)
	$(SAIL) -c $(SAIL_SRCS) -o $(basename $@)

$(EMULATOR): $(BUILD)/model.c $(C_DIR)/harness_hooks_noop.c $(C_DIR)/harness_hooks.h
	$(CC) $(C_FLAGS) $< $(C_DIR)/harness_hooks_noop.c $(C_SRCS) $(C_LIBS) -o $@

emulator: $(EMULATOR)

run: $(EMULATOR)
	./$(EMULATOR) $(RUN_FLAGS)

# --- Single-step test harness ------------------------------------------------
# A second front end for the same model: instead of running a program to a
# halt, it reads a line-oriented command stream (RESET / SET / MEM / OPCODE /
# STEP) and reports, per instruction, the whole architected state plus the
# footprint — which registers were written, which physical addresses were
# read, written and fetched.  See c/harness.c for the protocol.
#
# It needs a model WITHOUT sail's generated main(), since it supplies its own,
# so the C is generated a second time with --c-no-main.  Generating into its
# own directory keeps the header called model.h, which is what the generated
# .c includes.
HARNESS := $(BUILD)/ppc_$(CORE)_harness
HARNESS_COV := $(BUILD)/ppc_$(CORE)_harness_cov
HARNESS_SRCS := $(C_DIR)/harness.c
HARNESS_DEPS := $(HARNESS_SRCS) $(C_DIR)/harness_hooks.h

$(BUILD)/harness/model.c: $(SAIL_SRCS)
	mkdir -p $(dir $@)
	$(SAIL) -c --c-no-main $(SAIL_SRCS) -o $(basename $@)

$(HARNESS): $(BUILD)/harness/model.c $(HARNESS_DEPS)
	$(CC) $(C_FLAGS) -I $(dir $<) $< $(HARNESS_SRCS) $(C_SRCS) $(C_LIBS) -o $@

harness: $(HARNESS)

# Coverage build.  `sail -c --c-coverage <file>` instruments every branch and
# function entry and writes the full list of instrumentable locations to
# <file>; the running model then calls sail_branch_reached() and friends.
#
# Sail ships the runtime for those calls as lib/coverage/libsail_coverage.a,
# but it only ever accumulates into one global set and dumps it at exit, which
# cannot answer the question the vector generator asks ("what did THIS step
# cover?").  c/harness_cov.c provides the same five entry points with per-step
# bitmaps as well as the accumulated sailcov-format dump, so the stock library
# is deliberately not linked.  NOTE the `sailcov` post-processing tool is a
# separate Sail binary and is not required by, or used in, this build.
$(BUILD)/harness-cov/model.c: $(SAIL_SRCS)
	mkdir -p $(dir $@)
	$(SAIL) -c --c-no-main --c-coverage $(BUILD)/harness-cov/model.branches \
	        $(SAIL_SRCS) -o $(basename $@)

$(HARNESS_COV): $(BUILD)/harness-cov/model.c $(HARNESS_DEPS) \
                $(C_DIR)/harness_cov.c $(C_DIR)/harness_cov.h
	$(CC) $(C_FLAGS) -DPPC_HARNESS_COVERAGE=1 -I $(dir $<) $< \
	      $(HARNESS_SRCS) $(C_DIR)/harness_cov.c $(C_SRCS) $(C_LIBS) -o $@

harness-cov: $(HARNESS_COV)

# Exercise the harness end to end: instruction results, memory footprints,
# exceptions, determinism and batch throughput.  Pure shell + the harness.
harness-test: $(HARNESS)
	@$(TEST_DIR)/harness/run.sh ./$(HARNESS)

$(BUILD)/$(TEST_DIR)/%.elf: $(TEST_DIR)/%.S $(TEST_DIR)/link.ld $(TEST_DIR)/testlib.h
	@command -v $(TEST_CC) >/dev/null 2>&1 || \
	  { echo "$(TEST_CC) not found — install a powerpc cross toolchain"; \
	    echo "  (Debian/Ubuntu: apt-get install gcc-powerpc-linux-gnu)"; exit 1; }
	@mkdir -p $(dir $@)
	$(TEST_CC) -I $(TEST_DIR) $(TEST_LD_FLAGS) -o $@ $<

$(BUILD)/$(TEST_DIR)/%.bin: $(BUILD)/$(TEST_DIR)/%.elf
	$(TEST_OBJCOPY) -O binary $< $@

test-elfs: $(TEST_ELFS) $(TEST_BINS)

test: $(EMULATOR) $(TEST_ELFS) $(TEST_BINS)
	@fail=0; total=0; \
	for elf in $(TEST_ELFS); do \
	  name=$$(basename $$elf .elf); total=$$((total + 1)); \
	  entry=$$($(TEST_READELF) -h $$elf | awk '/Entry point address/ {print $$NF}'); \
	  ./$(EMULATOR) -b $(TEST_LOAD_ADDR),$(BUILD)/$(TEST_DIR)/$$name.bin \
	                -n $$entry -l $(TEST_STEP_LIMIT) \
	    | sed -n '/^\[halt\]\|^\[checkstop\]/,$$p' > $(BUILD)/$(TEST_DIR)/$$name.out; \
	  if diff -u $(TEST_DIR)/$$name.expected $(BUILD)/$(TEST_DIR)/$$name.out; then \
	    echo "PASS $$name"; \
	  else \
	    echo "FAIL $$name"; fail=$$((fail + 1)); \
	  fi; \
	done; \
	echo "$$((total - fail))/$$total tests passed"; \
	test $$fail -eq 0

# Run every test program with tracing on, which puts the disassembler over
# every instruction they execute: a missing or malformed `assembly` clause
# makes the emulator die of a match failure rather than print a line.
test-disasm: $(EMULATOR) $(TEST_ELFS) $(TEST_BINS)
	@for elf in $(TEST_ELFS); do \
	  name=$$(basename $$elf .elf); \
	  entry=$$($(TEST_READELF) -h $$elf | awk '/Entry point address/ {print $$NF}'); \
	  ./$(EMULATOR) -v 0x1 -b $(TEST_LOAD_ADDR),$(BUILD)/$(TEST_DIR)/$$name.bin \
	                -n $$entry -l $(TEST_STEP_LIMIT) > /dev/null \
	    || { echo "FAIL $$name: the emulator died while disassembling"; exit 1; }; \
	done; \
	echo "disassembled every instruction of $(words $(TEST_ELFS)) test programs"

# Rewrite every test/<name>.expected from what the model produces now.  Only
# for use after reading the diff `make test` printed and concluding the NEW
# output is the correct one.
test-accept: $(EMULATOR) $(TEST_ELFS) $(TEST_BINS)
	@for elf in $(TEST_ELFS); do \
	  name=$$(basename $$elf .elf); \
	  entry=$$($(TEST_READELF) -h $$elf | awk '/Entry point address/ {print $$NF}'); \
	  ./$(EMULATOR) -b $(TEST_LOAD_ADDR),$(BUILD)/$(TEST_DIR)/$$name.bin \
	                -n $$entry -l $(TEST_STEP_LIMIT) \
	    | sed -n '/^\[halt\]\|^\[checkstop\]/,$$p' > $(TEST_DIR)/$$name.expected; \
	  echo "accepted $$name"; \
	done

clean:
	rm -rf $(BUILD)
