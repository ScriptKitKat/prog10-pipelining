EID: pjy263
Priscilla Ye

# Requires Icarus Verilog (brew install icarus-verilog on macOS).

Compile + run a single testbench
iverilog -g2012 -o fpu_tb fpu_tb.sv && vvp fpu_tb
iverilog -g2012 -o alu_tb alu_tb.sv && vvp alu_tb
iverilog -g2012 -o memory_reg_tb memory_reg_tb.sv && vvp memory_reg_tb
iverilog -g2012 -o tinker_tb tinker_tb.sv && vvp tinker_tb

# View the waveform (requires GTKWave: brew install gtkwave)
gtkwave tinker_tb.vcd

Flags: -g2012 enables SystemVerilog-2012.

the FPU compile prints a few harmless "Numeric constant truncated to 53 bits" warnings from existing 53'h20000000000000 literals in fpu.sv

