# PRD: Pipelined Out-of-Order Tinker Processor

## 1. Introduction / Overview

The current Tinker processor is a multi-cycle FSM-based design where each instruction progresses sequentially through stages (FETCH -> DECODE -> EXECUTE -> MEMORY -> WRITEBACK). This means only one instruction is in-flight at any time, leaving most hardware idle each cycle.

This project transforms Tinker into a **pipelined, dual-issue, out-of-order (OOO) superscalar processor** based on Tomasulo's algorithm. The goal is to maximize instruction throughput by overlapping instruction execution, issuing multiple instructions per cycle, and executing instructions out of program order while committing results in order.

## 2. Goals

1. **Dual-issue pipeline**: Fetch, decode, and issue up to 2 instructions per cycle.
2. **Out-of-order execution**: Instructions execute as soon as operands are available, regardless of program order.
3. **In-order commit**: The reorder buffer (ROB) retires instructions in program order to maintain precise exceptions.
4. **Register renaming**: Eliminate WAR and WAW hazards using 128 physical registers mapped via a Register Alias Table (RAT).
5. **Forwarding via Common Data Bus (CDB)**: Broadcast results from functional units so dependent reservation stations can capture operands immediately.
6. **Store-to-load forwarding**: Loads check the store queue for matching addresses before going to memory.
7. **Pipelined execution units**: ALU (2 stages), FPU (4 stages) to improve clock frequency.
8. **Branch prediction**: 1-bit branch history table to reduce branch penalty.
9. **Load/store queues**: Decouple memory operations from execution, enforce memory ordering.
10. **Correctness**: All existing ISA instructions produce identical architectural results as the original single-issue Tinker.

## 3. Functional Requirements

### 3.1 Fetch Unit

- **FR-1**: Fetch up to 64 bytes (16 instructions) from memory starting at the current PC each cycle into a **fetch buffer**.
- **FR-2**: Supply 2 instructions per cycle to the decode stage (dual-issue) from the fetch buffer.
- **FR-3**: On a branch misprediction, flush the fetch buffer and redirect PC to the correct target.
- **FR-4**: Use a **1-bit Branch History Table (BHT)** indexed by lower PC bits to predict branch direction.
  - BHT size: 256 entries (indexed by `PC[9:2]`).
  - Prediction: taken or not-taken based on the 1-bit entry.
  - Update: flip the bit when the actual outcome differs from prediction.
- **FR-5**: For predicted-taken branches, fetch from the predicted target next cycle. For predicted-not-taken, continue sequential fetch.

### 3.2 Decode & Rename Unit

- **FR-6**: Decode up to 2 instructions per cycle. Extract opcode, rd, rs, rt, L fields from the 32-bit instruction encoding:
  ```
  [31:27] opcode | [26:22] rd | [21:17] rs | [16:12] rt | [11:0] L
  ```
- **FR-7**: Perform **register renaming** using a Register Alias Table (RAT):
  - RAT maps each of the 32 architectural registers to one of 128 physical registers.
  - On decode, rename the destination register (rd) to a free physical register from the **free list**.
  - Source registers (rs, rt) read their current physical mapping from the RAT.
- **FR-8**: Allocate a **reorder buffer (ROB) entry** for each decoded instruction. The ROB entry stores:
  - Instruction type (ALU, FPU, LOAD, STORE, BRANCH, other)
  - Destination architectural register
  - Old physical register mapping (for recovery on flush)
  - New physical register mapping
  - Completion status
  - Branch prediction info (for branches)
  - Store address and data (for stores)
  - PC of the instruction
- **FR-9**: If the ROB is full or the free list is empty, stall decode until resources become available.
- **FR-10**: Dispatch decoded instructions to the appropriate **reservation station** based on instruction type.

### 3.3 Register Alias Table (RAT)

- **FR-11**: Maintain a mapping table of 32 entries (one per architectural register), each pointing to a physical register index (0-127).
- **FR-12**: On rename, update the mapping for the destination architectural register to the newly allocated physical register.
- **FR-13**: On branch misprediction or flush, restore the RAT to the state at the mispredicted branch using a **checkpoint** or **ROB walk-back** mechanism.
- **FR-14**: Support 2 simultaneous renames per cycle (dual-issue). Handle the case where instruction 2 reads a register that instruction 1 is renaming in the same cycle (intra-group dependency).

### 3.4 Physical Register File

- **FR-15**: 128 registers, each 64 bits wide.
- **FR-16**: 4 read ports and 2 write ports (as specified by the microarchitecture).
- **FR-17**: Reads are combinational (same-cycle). Writes occur on the clock edge.
- **FR-18**: A **ready bit** per physical register indicates whether the value has been written. Reservation stations check this to determine operand availability.

### 3.5 Architectural Register File (reg_file)

- **FR-19**: Retain the existing `reg_file` module (32 x 64-bit registers) for committed architectural state.
- **FR-20**: Extend the interface to support 4 read ports and 2 write ports.
- **FR-21**: On ROB commit, write the result from the physical register to the corresponding architectural register.
- **FR-22**: R31 remains initialized to `MEM_SIZE` (524288) on reset.

### 3.6 Reservation Stations

- **FR-23**: Provide separate reservation station pools for each functional unit type:
  - ALU reservation stations: 4 entries per ALU (8 total for 2 ALUs)
  - FPU reservation stations: 4 entries per FPU (8 total for 2 FPUs)
  - Load queue: 8 entries
  - Store queue: 8 entries
- **FR-24**: Each reservation station entry contains:
  - Operation (opcode)
  - Source operand 1 value or physical register tag (if not yet ready)
  - Source operand 2 value or physical register tag (if not yet ready)
  - Ready bits for each source operand
  - Destination physical register tag
  - ROB index
  - Immediate value (L field, sign-extended)
  - PC (for branches)
- **FR-25**: When both source operands are ready, the instruction is **eligible for issue** to the functional unit.
- **FR-26**: Listen on the **Common Data Bus (CDB)** each cycle. When a CDB broadcast matches a pending source tag, capture the value and mark that operand as ready.
- **FR-27**: If the reservation stations for a functional unit type are full, stall dispatch for that instruction type.

### 3.7 Functional Units

#### 3.7.1 ALU (2 units, 2-stage pipeline each)

- **FR-28**: Each ALU is a 2-stage pipeline:
  - Stage 1: Compute result (integer arithmetic, logic, shift operations).
  - Stage 2: Write result to CDB.
- **FR-29**: Supported operations per ALU: ADD, ADDI, SUB, SUBI, MUL, DIV, AND, OR, XOR, NOT, SHFTR, SHFTRI, SHFTL, SHFTLI, MOV, MOVI.
- **FR-30**: Branch resolution also occurs in the ALU: BR, BRR, BRR_L, BRNZ, BRGT, CALL, RETURN.
  - On branch resolution, compare actual outcome with prediction. If mispredicted, signal the ROB to initiate a pipeline flush.

#### 3.7.2 FPU (2 units, 4-stage pipeline each)

- **FR-31**: Each FPU is a 4-stage pipeline:
  - Stage 1: Operand classification and alignment (for add/sub) or partial computation.
  - Stage 2: Core computation.
  - Stage 3: Normalization.
  - Stage 4: Rounding and write result to CDB.
- **FR-32**: Supported operations per FPU: FADD, FSUB, FMUL, FDIV.
- **FR-33**: Reuse the existing `fpu_add`, `fpu_mul`, `fpu_div` combinational logic internally, but register the pipeline stages.

### 3.8 Common Data Bus (CDB)

- **FR-34**: The CDB has width to support results from all functional units. Each CDB entry carries:
  - Physical register tag (destination)
  - 64-bit result value
  - ROB index
  - Valid bit
- **FR-35**: Each cycle, completed functional unit results are broadcast on the CDB. If multiple units complete simultaneously, arbitrate (round-robin or priority-based) and stall the others for one cycle.
- **FR-36**: The following listeners capture CDB broadcasts:
  - Reservation stations (to resolve pending operands)
  - ROB (to mark instructions complete)
  - Physical register file (to write the result and set the ready bit)

### 3.9 Load/Store Queues

- **FR-37**: **Load queue** (8 entries): Holds pending load instructions with address, destination physical register tag, and ROB index.
- **FR-38**: **Store queue** (8 entries): Holds pending store instructions with address, data, and ROB index. Store data may arrive after the address is computed (via CDB).
- **FR-39**: **Store-to-load forwarding**: When a load computes its address, search the store queue (older stores only) for a matching address. If found and the store has data, forward the data to the load instead of reading memory.
- **FR-40**: **Memory ordering**: Loads may execute out-of-order with respect to other loads, but must check against older stores. Stores commit to memory **only** when they are the oldest instruction in the ROB (in-order commit).
- **FR-41**: Each L/S unit computes the effective address: `base_register + sign_extend(L)`.
- **FR-42**: Two L/S units can operate in parallel (one load and one store, or two loads, etc.), but memory has a single write port, so only one store can commit to memory per cycle.

### 3.10 Reorder Buffer (ROB)

- **FR-43**: Circular buffer with **32 entries**.
- **FR-44**: Instructions are allocated in program order at decode and committed in program order from the head.
- **FR-45**: Each ROB entry stores (see FR-8 for full field list).
- **FR-46**: **Commit logic**: Each cycle, commit up to 2 instructions from the ROB head (dual-commit to match dual-issue) if they are marked complete:
  - For ALU/FPU results: write physical register value to the architectural register file. Free the old physical register (return to free list).
  - For stores: write the store data to memory via the memory module's write port. Only one store can write to memory per cycle.
  - For branches: no additional action if correctly predicted. If mispredicted, this was already handled at resolution time.
- **FR-47**: **Misprediction flush**: When a branch misprediction is detected:
  1. Flush all ROB entries after the mispredicted branch.
  2. Restore the RAT from the checkpoint or by walking back the ROB.
  3. Return freed physical registers from flushed instructions to the free list.
  4. Redirect PC to the correct branch target.
  5. Flush fetch buffer, reservation stations, and in-flight pipeline stages.
- **FR-48**: **HALT handling**: When a HALT instruction reaches the ROB head and all prior instructions are committed, assert the `hlt` output signal.

### 3.11 Memory Module

- **FR-49**: Retain the existing `memory` module interface and extend as needed.
- **FR-50**: Memory supports:
  - Instruction fetch: 64 bytes per cycle starting at PC (to fill the fetch buffer).
  - Data read: 1 load per cycle (64-bit).
  - Data write: 1 store per cycle (64-bit), only on ROB commit.
- **FR-51**: The instruction fetch port and data ports operate independently (Harvard-style from the pipeline's perspective, though backed by the same memory array).

### 3.12 Pipeline Stages (Overall)

The full pipeline:

```
Fetch -> Decode/Rename -> Dispatch -> Issue -> Execute -> Complete (CDB) -> Commit
```

- **Fetch**: Read instructions from memory into fetch buffer. Apply branch prediction.
- **Decode/Rename**: Decode up to 2 instructions. Rename registers. Allocate ROB entries.
- **Dispatch**: Send instructions to reservation stations.
- **Issue**: When operands are ready, send instruction from reservation station to functional unit.
- **Execute**: ALU (2 stages), FPU (4 stages), L/S (address compute + memory access).
- **Complete**: Broadcast result on CDB. Mark ROB entry complete.
- **Commit**: Retire instructions in order from ROB head. Update architectural state.

### 3.13 ISA Compatibility

- **FR-52**: All 30 instructions from the existing Tinker ISA must be supported with identical semantics:
  - Integer arithmetic: ADD, ADDI, SUB, SUBI, MUL, DIV
  - Logic: AND, OR, XOR, NOT
  - Shift: SHFTR, SHFTRI, SHFTL, SHFTLI
  - Branch: BR, BRR, BRR_L, BRNZ, BRGT
  - Call/Return: CALL, RETURN
  - Load/Store: LOAD, STORE
  - Move: MOV, MOVI
  - Float: FADD, FSUB, FMUL, FDIV
  - Privileged: HALT
- **FR-53**: Instruction encoding is unchanged: `[31:27] opcode | [26:22] rd | [21:17] rs | [16:12] rt | [11:0] L`.

## 5. Design Considerations

### 5.1 Module Hierarchy

```
tinker_top
├── fetch_unit
│   ├── fetch_buffer (16-instruction queue)
│   └── branch_predictor (1-bit BHT, 256 entries)
├── decode_rename_unit
│   ├── decoder (x2 for dual-issue)
│   ├── rat (Register Alias Table)
│   └── free_list (physical register free list)
├── dispatch_unit
├── reservation_stations
│   ├── rs_alu (8 entries, 4 per ALU)
│   ├── rs_fpu (8 entries, 4 per FPU)
│   ├── rs_load (8 entries)
│   └── rs_store (8 entries)
├── functional_units
│   ├── alu_pipe_0 (2-stage pipelined ALU)
│   ├── alu_pipe_1 (2-stage pipelined ALU)
│   ├── fpu_pipe_0 (4-stage pipelined FPU)
│   └── fpu_pipe_1 (4-stage pipelined FPU)
├── load_store_unit
│   ├── load_queue (8 entries)
│   └── store_queue (8 entries)
├── cdb (Common Data Bus + arbiter)
├── rob (Reorder Buffer, 32 entries)
├── phys_reg_file (128 x 64-bit, 4R/2W)
├── reg_file (32 x 64-bit, architectural)
└── memory (512KB, byte-addressable)
```

### 5.2 Key Data Widths

| Signal | Width | Description |
|--------|-------|-------------|
| Physical register tag | 7 bits | Index into 128 physical registers |
| Architectural register | 5 bits | Index into 32 architectural registers |
| ROB index | 5 bits | Index into 32-entry ROB |
| Opcode | 5 bits | Instruction opcode |
| Immediate (L) | 12 bits | Sign-extended to 64 bits |
| Data | 64 bits | Register/memory data width |
| Instruction | 32 bits | Fixed instruction width |
| BHT index | 8 bits | `PC[9:2]` |

### 5.3 Cycle-by-Cycle Pipeline Diagram

```
Cycle:    1    2    3    4    5    6    7    8    9
Inst A:  FE   DR   DI   IS   EX1  EX2  CDB  COM
Inst B:  FE   DR   DI   IS   EX1  EX2  CDB  COM
Inst C:       FE   DR   DI   IS   EX1  EX2  CDB  COM
Inst D:       FE   DR   DI   IS   EX1  EX2  CDB  COM
```

- FE = Fetch, DR = Decode/Rename, DI = Dispatch, IS = Issue
- EX1-EX2 = ALU execute (2 stages), CDB = Complete/broadcast, COM = Commit
- FPU instructions would have EX1-EX4 (4 stages)

## 6. Technical Considerations

1. **Simulation tool**: `iverilog -g2012` with SystemVerilog 2012. All modules must compile under this toolchain.
2. **Existing FPU reuse**: The combinational `fpu_add`, `fpu_mul`, `fpu_div` modules should be wrapped inside pipelined FPU stages, not rewritten.
3. **CDB contention**: With 2 ALUs, 2 FPUs, and 2 L/S units, up to 6 results could complete in one cycle. The CDB must arbitrate. Consider 2 CDB buses (one per issue slot) or priority arbitration with stall.
4. **Free list implementation**: A FIFO of physical register indices. Initialize with registers 32-127 (registers 0-31 initially map 1:1 to architectural registers).
5. **RAT checkpoint**: For branch misprediction recovery, snapshot the RAT when a branch is dispatched. Store the snapshot in the ROB entry or a separate checkpoint buffer.
6. **CALL/RETURN**: CALL writes `PC+4` to `mem[r31-8]` and jumps to rd. RETURN reads from `mem[r31-8]`. These use the load/store queue and must be ordered correctly.
7. **MOVI special handling**: MOVI only modifies bits [11:0] of rd, leaving [63:12] unchanged. This creates a read-modify-write dependency on the destination register.

## 7. Success Metrics

1. **Correctness**: All existing testbench programs produce identical final architectural register and memory state as the original single-issue Tinker.
2. **Cycle count reduction**: For programs with instruction-level parallelism, the pipelined processor completes in fewer cycles than the original.
3. **Compilation**: All modules compile cleanly with `iverilog -g2012` (warnings acceptable, errors are not).
4. **Waveform verifiability**: Pipeline stages, CDB broadcasts, ROB state, and RAT mappings are observable via VCD dump.

## Extra Notes

1. **CDB bus count**: There should be be 2 CDB buses (matching dual-issue)
2. **MOVI behavior**: MOVI should be redefined to zero-extend L into rd? (Current ISA: read-modify-write. Preserving this means MOVI has a source dependency on rd.)
3. **CALL/RETURN and R31**: R31 modifications by CALL/RETURN (decrement/increment the stack pointer) be handled as explicit register writes through the rename path
4. **Memory latency**: Memory remain single-cycle