EID: pjy263
Priscilla Ye

# Pipelined Tinker Processor

A dual-issue, out-of-order superscalar processor implemented in SystemVerilog. This design transforms the original single-cycle Tinker processor into a dynamically scheduled pipeline using Tomasulo's algorithm.

## Repository layout

| Directory | Contents |
|-----------|----------|
| `tinker.sv` | Top-level processor (at repo root; required for typical course submissions) |
| `hdl/` | All other RTL module definitions (`.sv`) |
| `test/` | Testbenches (`*_tb.sv`) |
| `sim/` | Waveform dumps from simulation (`.vcd`) |
| `vvp/` | Optional copies of compiled simulation binaries (not required to build) |

Build and run commands below assume the **repository root** as the current working directory so that `$dumpfile` paths and include search paths resolve correctly.

### Include paths (`-I . -I hdl`)

- **`-I .`** — finds `tinker.sv` at the top level (what `test/tinker_tb.sv` includes with `` `include "tinker.sv"``).
- **`-I hdl`** — finds every other module included from `tinker.sv` (e.g. `` `include "alu.sv"`` → `hdl/alu.sv`).

If you omit **`-I .`**, compilation fails because `tinker.sv` is not in `hdl/`.

### `vvp` is the simulator program

**`vvp`** is the Icarus Verilog **executable** (install the `icarus-verilog` package so `vvp` is on your `PATH`). That is different from the optional **`vvp/`** directory, which only holds extra build products if you choose to put them there.

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
| `hdl/fetch_unit.sv` | PC, 16-entry instruction FIFO, branch prediction (BHT) |
| `hdl/decode_rename.sv` | Dual-issue decoder, register renaming, dispatch logic |
| `hdl/reservation_station.sv` | Parameterized RS with CDB wakeup and oldest-ready issue |
| `hdl/alu_pipe.sv` | 2-stage ALU pipeline with branch resolution |
| `hdl/fpu_pipe.sv` | 4-stage FPU pipeline wrapping combinational FPU |
| `hdl/load_store_queue.sv` | 8-entry load queue + 8-entry store queue with forwarding |
| `hdl/cdb.sv` | 2-bus CDB with round-robin arbiter (6 sources) |
| `hdl/rob.sv` | 32-entry circular ROB for in-order commit |

### Register Management

| File | Description |
|------|-------------|
| `hdl/phys_reg_file.sv` | 128 x 64-bit physical register file (4R / 2W ports) |
| `hdl/rat.sv` | 32-entry RAT with checkpoint/restore and intra-group forwarding |
| `hdl/free_list.sv` | 96-entry FIFO of available physical register indices |

### Supporting / Legacy

| File | Description |
|------|-------------|
| `hdl/memory_reg.sv` | 512 KB memory + 32 x 64-bit architectural register file |
| `hdl/alu.sv` | Combinational ALU (wrapped by `alu_pipe.sv`) |
| `hdl/fpu.sv` | Combinational FPU units (wrapped by `fpu_pipe.sv`) |
| `hdl/tinker_multicycle.sv` | Original single-issue multicycle FSM (reference) |

## Testbenches

| Testbench | Tests |
|-----------|-------|
| `test/tinker_tb.sv` | Full processor integration (ALU, dual-issue, load/store, branches, FPU, mixed ILP) |
| `test/fetch_unit_tb.sv` | Sequential fetch, branch prediction, flush |
| `test/decode_rename_tb.sv` | Opcode decode, register renaming, stall logic |
| `test/rs_tb.sv` | Dispatch, CDB wakeup, issue selection, flush |
| `test/rob_tb.sv` | Allocate, complete, commit, store commit, flush |
| `test/cdb_tb.sv` | Arbitration, round-robin, stalling |
| `test/eu_tb.sv` | ALU/FPU pipeline stages, branch resolution |
| `test/lsq_tb.sv` | Load/store dispatch, forwarding, commit |
| `test/rat_tb.sv` | Rename, intra-group forwarding, checkpoint/restore |
| `test/memory_reg_tb.sv` | Memory read/write, register ports |
| `test/alu_tb.sv` | Integer arithmetic and logic |
| `test/fpu_tb.sv` | Floating-point add, sub, mul, div |

## Building and Running

Requires [Icarus Verilog](https://github.com/steveicarus/iverilog): both **`iverilog`** and **`vvp`** must be on your `PATH` (e.g. `brew install icarus-verilog` on macOS).

### Recommended: Makefile (writes `tinker_tb` in the repo root)

```bash
make          # compile → ./tinker_tb
make run-tinker   # compile (if needed) and vvp tinker_tb
```

### Manual: full processor test

```bash
iverilog -g2012 -I . -I hdl -o tinker_tb test/tinker_tb.sv
vvp tinker_tb
```

### Other testbenches

Use the same flags **`-g2012 -I . -I hdl`**, change the output name and source file:

```bash
iverilog -g2012 -I . -I hdl -o rob_tb test/rob_tb.sv && vvp rob_tb
iverilog -g2012 -I . -I hdl -o cdb_tb test/cdb_tb.sv && vvp cdb_tb
# ... same pattern for rs_tb, lsq_tb, rat_tb, fetch_unit_tb, decode_rename_tb, eu_tb, memory_reg_tb, alu_tb, fpu_tb
```

To place the executable under `vvp/` instead (optional):

```bash
iverilog -g2012 -I . -I hdl -o vvp/tinker_tb test/tinker_tb.sv && vvp vvp/tinker_tb
```

### Waveforms

```bash
gtkwave sim/tinker_tb.vcd
```

`-g2012` enables SystemVerilog-2012. The FPU compile prints harmless "Numeric constant truncated to 53 bits" warnings from `hdl/fpu.sv`.
