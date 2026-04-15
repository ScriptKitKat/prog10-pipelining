# Pipelined Tinker — Icarus Verilog build
# Requires: iverilog and vvp on PATH (e.g. brew install icarus-verilog)
#
# Include paths: "." finds tinker.sv at repo root; "hdl" finds all other RTL.
IVERILOG  := iverilog
VVP       := vvp
IVFLAGS   := -g2012 -I . -I hdl

# Default: build simulation binary in current directory (typical autograder layout).
.PHONY: all tinker_tb run-tinker clean

all: tinker_tb

tinker_tb: test/tinker_tb.sv tinker.sv
	$(IVERILOG) $(IVFLAGS) -o tinker_tb test/tinker_tb.sv

run-tinker: tinker_tb
	$(VVP) tinker_tb

clean:
	rm -f tinker_tb
