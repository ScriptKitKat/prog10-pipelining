EID: pjy263
Priscilla Ye

# Pipelined Tinker Processor

A dual-issue, out-of-order superscalar processor implemented in SystemVerilog. This design transforms the original single-cycle Tinker processor into a dynamically scheduled pipeline using Tomasulo's algorithm.

## Architecture

```
Fetch --> Decode/Rename --> Dispatch --> Issue --> Execute --> Complete (CDB) --> Commit
```

### Key Features

- **Dual-issue**: up to 2 instructions fetched, decoded, dispatched, and committed per cycle
- **Out-of-order execution** with in-order commit via a 32-entry Reorder Buffer (ROB)
- **Register renaming**: 128 physical registers (64-bit) mapped through a Register Alias Table (RAT)
- **Tomasulo-style reservation stations** with CDB snooping and oldest-ready issue
- **2 Common Data Buses** with round-robin arbitration across 6 sources
- **1-bit Branch History Table** (256 entries) with flush-on-mispredict recovery
- **Store-to-load forwarding** via an 8+8 entry Load/Store Queue

### Execution Units

| Unit | Count | Latency | Operations |
|------|-------|---------|------------|
| ALU pipeline | 2 | 2 cycles | ADD, SUB, MUL, DIV, AND, OR, XOR, NOT, shifts, branches, MOV |
| FPU pipeline | 2 | 4 cycles | FADD, FSUB, FMUL, FDIV |
| Load/Store | 1 | variable | LOAD, STORE (1 store commit/cycle) |

## Module Map

### Core Pipeline

| File | Description |
|------|-------------|
| `tinker.sv` | Top-level processor integrating all components |
| `fetch_unit.sv` | PC, 16-entry instruction FIFO, branch prediction (BHT) |
| `decode_rename.sv` | Dual-issue decoder, register renaming, dispatch logic |
| `reservation_station.sv` | Parameterized RS with CDB wakeup and oldest-ready issue |
| `alu_pipe.sv` | 2-stage ALU pipeline with branch resolution |
| `fpu_pipe.sv` | 4-stage FPU pipeline wrapping combinational FPU |
| `load_store_queue.sv` | 8-entry load queue + 8-entry store queue with forwarding |
| `cdb.sv` | 2-bus CDB with round-robin arbiter (6 sources) |
| `rob.sv` | 32-entry circular ROB for in-order commit |

### Register Management

| File | Description |
|------|-------------|
| `phys_reg_file.sv` | 128 x 64-bit physical register file (4R / 2W ports) |
| `rat.sv` | 32-entry RAT with checkpoint/restore and intra-group forwarding |
| `free_list.sv` | 96-entry FIFO of available physical register indices |

### Supporting / Legacy

| File | Description |
|------|-------------|
| `memory_reg.sv` | 512 KB memory + 32 x 64-bit architectural register file |
| `alu.sv` | Combinational ALU (wrapped by `alu_pipe.sv`) |
| `fpu.sv` | Combinational FPU units (wrapped by `fpu_pipe.sv`) |
| `tinker_multicycle.sv` | Original single-issue multicycle FSM (reference) |

## Testbenches

| Testbench | Tests |
|-----------|-------|
| `tinker_tb.sv` | Full processor integration (ALU, dual-issue, load/store, branches, FPU, mixed ILP) |
| `fetch_unit_tb.sv` | Sequential fetch, branch prediction, flush |
| `decode_rename_tb.sv` | Opcode decode, register renaming, stall logic |
| `rs_tb.sv` | Dispatch, CDB wakeup, issue selection, flush |
| `rob_tb.sv` | Allocate, complete, commit, store commit, flush |
| `cdb_tb.sv` | Arbitration, round-robin, stalling |
| `eu_tb.sv` | ALU/FPU pipeline stages, branch resolution |
| `lsq_tb.sv` | Load/store dispatch, forwarding, commit |
| `rat_tb.sv` | Rename, intra-group forwarding, checkpoint/restore |
| `memory_reg_tb.sv` | Memory read/write, register ports |
| `alu_tb.sv` | Integer arithmetic and logic |
| `fpu_tb.sv` | Floating-point add, sub, mul, div |

## Building and Running

Requires [Icarus Verilog](https://github.com/steveicarus/iverilog) (`brew install icarus-verilog` on macOS).

```bash
# Compile and run a testbench
iverilog -g2012 -o tinker_tb tinker_tb.sv && vvp tinker_tb
iverilog -g2012 -o rob_tb rob_tb.sv && vvp rob_tb
iverilog -g2012 -o rs_tb rs_tb.sv && vvp rs_tb
iverilog -g2012 -o cdb_tb cdb_tb.sv && vvp cdb_tb
iverilog -g2012 -o lsq_tb lsq_tb.sv && vvp lsq_tb
iverilog -g2012 -o rat_tb rat_tb.sv && vvp rat_tb
iverilog -g2012 -o fetch_unit_tb fetch_unit_tb.sv && vvp fetch_unit_tb
iverilog -g2012 -o decode_rename_tb decode_rename_tb.sv && vvp decode_rename_tb
iverilog -g2012 -o eu_tb eu_tb.sv && vvp eu_tb
iverilog -g2012 -o memory_reg_tb memory_reg_tb.sv && vvp memory_reg_tb
iverilog -g2012 -o alu_tb alu_tb.sv && vvp alu_tb
iverilog -g2012 -o fpu_tb fpu_tb.sv && vvp fpu_tb

# View waveforms (requires GTKWave: brew install gtkwave)
gtkwave tinker_tb.vcd
```

`-g2012` enables SystemVerilog-2012. The FPU compile prints harmless "Numeric constant truncated to 53 bits" warnings from `fpu.sv`.