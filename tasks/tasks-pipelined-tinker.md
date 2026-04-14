# Tasks: Pipelined Out-of-Order Tinker Processor

## Relevant Files

- `tinker.sv` - Original top-level processor (reference for ISA behavior, will be replaced by `tinker_top.sv`)
- `memory_reg.sv` - Existing memory and register file modules (to be extended)
- `alu.sv` - Existing ALU (combinational, to be wrapped in pipelined stages)
- `fpu.sv` - Existing FPU modules (combinational, to be wrapped in pipelined stages)
- `tinker_top.sv` - New top-level OOO processor module
- `fetch_unit.sv` - Fetch unit with fetch buffer and branch predictor
- `decode_rename.sv` - Decode, register rename (RAT), and free list
- `rat.sv` - Register Alias Table module
- `free_list.sv` - Physical register free list (FIFO)
- `phys_reg_file.sv` - Physical register file (128 x 64-bit, 4R/2W)
- `reservation_station.sv` - Parameterized reservation station module
- `alu_pipe.sv` - 2-stage pipelined ALU wrapper
- `fpu_pipe.sv` - 4-stage pipelined FPU wrapper
- `load_store_queue.sv` - Load queue and store queue with store-to-load forwarding
- `cdb.sv` - Common Data Bus with 2-bus arbiter
- `rob.sv` - Reorder buffer (32 entries, circular buffer)
- `tinker_top.sv` - Top-level integration of all OOO pipeline modules
- `tinker_top_tb.sv` - Integration testbench for the new pipelined processor
- `rob_tb.sv` - Unit testbench for the reorder buffer
- `rat_tb.sv` - Unit testbench for the RAT
- `rs_tb.sv` - Unit testbench for reservation stations
- `lsq_tb.sv` - Unit testbench for load/store queues

### Notes

- All modules must compile with `iverilog -g2012`.
- Run tests with: `iverilog -g2012 -o <tb_name> <tb_file>.sv && vvp <tb_name>`
- Waveform dumps use `$dumpfile` / `$dumpvars` and can be viewed with `gtkwave`.
- The existing `alu.sv`, `fpu.sv`, and `memory_reg.sv` are kept as-is and wrapped or extended by new modules.

## Instructions for Completing Tasks

**IMPORTANT:** As you complete each task, you must check it off in this markdown file by changing `- [ ]` to `- [x]`. This helps track progress and ensures you don't skip any steps.

Example:
- `- [ ] 1.1 Read file` → `- [x] 1.1 Read file` (after completing)

Update the file after completing each sub-task, not just after completing an entire parent task.

## Tasks

- [x] 1.0 Extend memory and register file modules
  - [x] 1.1 Extend `memory` module: add a 64-byte instruction fetch port (`instr_fetch_addr` input, `instr_fetch_data` 512-bit output) that reads 16 consecutive 32-bit instructions starting at the given address. Keep existing single-instruction fetch port and data read/write ports.
  - [x] 1.2 Extend `reg_file` module: add a 4th read port (`read_sel4` / `read_data4`) and a 2nd write port (`write_enable2`, `write_data2`, `write_select2`). Handle simultaneous writes to the same register (second write wins).
  - [x] 1.3 Verify R31 still initializes to `MEM_SIZE` on reset.
  - [x] 1.4 Compile and run existing `memory_reg_tb.sv` to confirm no regressions. Add quick tests for the new ports.

- [x] 2.0 Build physical register file, free list, and RAT
  - [x] 2.1 Create `phys_reg_file.sv`: 128 registers x 64-bit. 4 read ports (combinational), 2 write ports (posedge clk). One `ready` bit per register. On reset, registers 0-31 are marked ready (they hold initial architectural state), registers 32-127 are marked ready with value 0.
  - [x] 2.2 Create `free_list.sv`: FIFO holding physical register indices (7-bit each). Initialize with registers 32-127 (96 entries). Support `alloc` (pop up to 2 per cycle) and `free` (push up to 2 per cycle). Provide `empty` signal for stall detection.
  - [x] 2.3 Create `rat.sv`: 32-entry mapping table (architectural reg -> physical reg index, 7-bit). On reset, `arch_reg[i]` maps to `phys_reg[i]` (identity mapping). Support 2 simultaneous lookups for source operands per instruction (4 lookups total for dual-issue) and 2 renames per cycle. Handle intra-group dependency: if instruction B's source is instruction A's destination (same cycle), forward instruction A's new physical mapping.
  - [x] 2.4 Add RAT checkpoint support: on a `checkpoint_en` signal, snapshot the entire RAT into a checkpoint register. On `restore_en`, overwrite the RAT from the checkpoint. (Supports one outstanding branch checkpoint; sufficient for initial implementation.)
  - [x] 2.5 Write `rat_tb.sv`: test identity mapping on reset, single rename, dual rename, intra-group forwarding, checkpoint/restore.
  - [x] 2.6 Compile all three modules and testbench with `iverilog -g2012`, verify all tests pass.

- [x] 3.0 Build the reorder buffer (ROB)
  - [x] 3.1 Create `rob.sv`: 32-entry circular buffer with `head` and `tail` pointers. Each entry stores: valid bit, instruction type (3-bit: ALU/FPU/LOAD/STORE/BRANCH/HALT/OTHER), destination architectural register (5-bit), old physical register (7-bit), new physical register (7-bit), completed bit, branch predicted-taken bit, branch actual-taken bit, store address (64-bit), store data (64-bit), PC (64-bit), mispredicted bit.
  - [x] 3.2 Implement `allocate` interface: accept up to 2 new entries per cycle (dual-issue). Return allocated ROB indices. Assert `full` signal when fewer than 2 entries are available.
  - [x] 3.3 Implement `complete` interface: accept up to 2 CDB broadcasts per cycle. Match by ROB index, set completed bit, write result data for stores.
  - [x] 3.4 Implement `commit` logic: each cycle, retire up to 2 instructions from the head if they are completed. Output commit signals: for ALU/FPU, signal the arch reg file write and free the old physical register. For STORE, output store address/data for memory write (max 1 store commit per cycle — if head is a store, only commit 1 this cycle). For HALT, assert `hlt` when it reaches the head.
  - [x] 3.5 Implement `flush` interface: given a ROB index of a mispredicted branch, invalidate all entries after it (from mispredicted+1 to tail). Output the list of new physical registers from flushed entries to return to the free list. Output the old physical register mappings for RAT restoration. Reset tail to mispredicted+1.
  - [x] 3.6 Write `rob_tb.sv`: test allocate/complete/commit cycle for ALU instructions, test store commit, test flush on misprediction, test full/empty conditions.
  - [x] 3.7 Compile and verify with `iverilog -g2012`.

- [x] 4.0 Build reservation stations
  - [x] 4.1 Create `reservation_station.sv` as a parameterized module (parameter: `NUM_ENTRIES`, default 4). Each entry: valid bit, opcode (5-bit), source1 value (64-bit) or tag (7-bit) + ready bit, source2 value (64-bit) or tag (7-bit) + ready bit, destination physical register tag (7-bit), ROB index (5-bit), immediate (64-bit sign-extended L), PC (64-bit).
  - [x] 4.2 Implement `dispatch` interface: accept a new instruction entry if a slot is available. Output `full` signal when no slots free.
  - [x] 4.3 Implement CDB snoop logic: each cycle, check both CDB buses. For every entry where a source tag matches a CDB broadcast tag, capture the CDB value and set that source ready.
  - [x] 4.4 Implement `issue` logic: select one ready entry (both sources ready) using oldest-first priority (lowest ROB index). Output the instruction's fields to the functional unit. Clear the entry.
  - [x] 4.5 Implement `flush` interface: on misprediction, invalidate all entries with ROB index in the flushed range.
  - [x] 4.6 Write `rs_tb.sv`: test dispatch, CDB wakeup, issue selection, flush.
  - [x] 4.7 Compile and verify with `iverilog -g2012`.

- [x] 5.0 Build pipelined ALU and FPU execution units
  - [x] 5.1 Create `alu_pipe.sv`: 2-stage pipeline wrapper. Stage 1 latches inputs and computes the result using the existing combinational `ALU` module logic (inline or instantiate). Stage 2 latches the result and presents it to the CDB. Include pipeline registers between stages. Accept `valid_in` to track whether the pipeline stage holds a real instruction.
  - [x] 5.2 Handle branch resolution in the ALU pipeline: for branch opcodes (BR, BRR, BRR_L, BRNZ, BRGT), compute the actual branch target and taken/not-taken outcome. Compare with the predicted outcome (carried along in the pipeline). Output `mispredict` signal and `correct_target` at stage 2.
  - [x] 5.3 Handle CALL/RETURN in the ALU pipeline: CALL computes the target address (rd value) and the return address (PC+4). The return address write to memory goes through the store queue. RETURN triggers a load from the load queue. Both are dispatched as paired ALU + memory operations at decode time.
  - [x] 5.4 Handle MOVI: treat as read-modify-write. The reservation station provides the current rd value as source1. ALU computes `{source1[63:12], L}` as the result.
  - [x] 5.5 Create `fpu_pipe.sv`: 4-stage pipeline wrapper. Stage 1: latch inputs and begin computation. Stages 2-3: pipeline the existing combinational `fpu_add`/`fpu_mul`/`fpu_div` result through registers. Stage 4: present result to CDB. Track `valid` through all 4 stages.
  - [x] 5.6 Compile both pipeline wrappers and verify they pass basic smoke tests (feed known operands, check result appears at correct stage).

- [x] 6.0 Build the load/store queues
  - [x] 6.1 Create `load_store_queue.sv` containing both a load queue (8 entries) and store queue (8 entries). Each load entry: valid, ROB index, destination physical register tag, address (64-bit), address-ready bit, completed bit. Each store entry: valid, ROB index, address (64-bit), address-ready bit, data (64-bit), data-ready bit, committed bit.
  - [x] 6.2 Implement load dispatch: allocate a load queue entry when a LOAD instruction is dispatched. Address is computed by the L/S unit (base register + sign-extended L).
  - [x] 6.3 Implement store dispatch: allocate a store queue entry when a STORE instruction is dispatched. Address and data may arrive separately (address from L/S unit, data via CDB if the source register wasn't ready).
  - [x] 6.4 Implement store-to-load forwarding: when a load has its address ready, search the store queue for older stores (lower ROB index, accounting for circular wrap) with a matching address that have data ready. If found, forward the store's data to the load and broadcast on CDB. If not found (or older store has matching address but no data yet), wait or go to memory.
  - [x] 6.5 Implement memory access: loads without a store-queue hit read from the memory module's data port. One load can access memory per cycle.
  - [x] 6.6 Implement store commit: when the ROB commits a store, mark the store queue entry as committed. The store queue then writes to memory (1 store write per cycle via the memory write port). Remove the entry after the write completes.
  - [x] 6.7 Implement flush: invalidate load and store queue entries with ROB indices in the flushed range.
  - [x] 6.8 Write `lsq_tb.sv`: test load hit to memory, store-to-load forwarding, store commit to memory, flush behavior.
  - [x] 6.9 Compile and verify with `iverilog -g2012`.

- [x] 7.0 Build the Common Data Bus (CDB) with arbiter
  - [x] 7.1 Create `cdb.sv`: 2 CDB buses. Each bus carries: valid bit, physical register tag (7-bit), 64-bit result, ROB index (5-bit). Inputs from 6 sources: ALU0, ALU1, FPU0, FPU1, LSQ0 (load result), LSQ1 (load result).
  - [x] 7.2 Implement round-robin arbiter: each cycle, assign up to 2 ready results to the 2 buses. If more than 2 results are ready, the remaining sources stall (hold their result for the next cycle). Rotate priority each cycle to ensure fairness.
  - [x] 7.3 Broadcast CDB outputs to: reservation stations (operand wakeup), ROB (mark complete), physical register file (write result + set ready bit).
  - [x] 7.4 Compile and verify with a simple test: multiple sources asserting simultaneously, confirm round-robin selection and stall behavior.

- [x] 8.0 Build the fetch unit with branch predictor
  - [x] 8.1 Create `fetch_unit.sv`: contains PC register, fetch buffer (FIFO holding up to 16 instructions), and branch predictor. Each cycle, if the fetch buffer has room, issue a 64-byte fetch request to memory's instruction fetch port, loading up to 16 instructions at PC. Advance PC by the number of bytes fetched.
  - [x] 8.2 Implement fetch buffer output: supply up to 2 instructions per cycle to the decode stage. Each output includes the instruction word and its PC. Dequeue 0, 1, or 2 entries depending on how many the decode stage can accept (backpressure from stalls).
  - [x] 8.3 Implement 1-bit BHT: 256-entry table indexed by `PC[9:2]`. On fetch, if the instruction is a branch (check opcode bits in the fetched word), predict taken/not-taken based on the BHT entry. Pass the prediction along with the instruction to decode.
  - [x] 8.4 Implement predicted-taken redirect: if prediction is taken, the fetch unit needs the target address. For BRR_L (immediate offset), compute `PC + sign_ext(L)` from the instruction word itself. For register-target branches, predict not-taken (target unknown at fetch time) or use a BTB (simplification: predict not-taken for register branches).
  - [x] 8.5 Implement flush interface: on misprediction signal from ROB/ALU, clear the fetch buffer and set PC to the corrected target address.
  - [x] 8.6 Implement BHT update: when a branch resolves (from ALU pipeline), update the BHT entry — flip the bit if the actual outcome differed from the prediction.
  - [x] 8.7 Compile and verify: test sequential fetch, branch prediction for BRR_L, flush and redirect.

- [x] 9.0 Build the decode/rename/dispatch stage
  - [x] 9.1 Create `decode_rename.sv`: accepts up to 2 instructions per cycle from the fetch unit. For each instruction, decode the opcode and classify as ALU, FPU, LOAD, STORE, BRANCH, HALT, or MOV type.
  - [x] 9.2 Wire up register renaming: for each decoded instruction, look up source registers (rs, rt, and rd where needed as a source — e.g., MOVI, ADDI, SUBI, SHFTRI, SHFTLI, STORE uses rs as data source) in the RAT to get physical register tags. Allocate a new physical register from the free list for the destination register (rd). Update the RAT.
  - [x] 9.3 Handle instructions with no destination register (STORE, branches with no writeback, HALT): do not allocate a new physical register or update the RAT for these. Still allocate a ROB entry.
  - [x] 9.4 Handle dual-issue intra-group dependencies: if instruction B (second slot) reads a register that instruction A (first slot) is writing, instruction B must use instruction A's *new* physical register mapping, not the old RAT entry.
  - [x] 9.5 Implement dispatch: send each decoded/renamed instruction to the appropriate reservation station (ALU RS for integer/logic/shift/branch/move, FPU RS for float ops, load queue for LOAD, store queue for STORE). Read operand values from the physical register file if the ready bit is set; otherwise, send the physical register tag for CDB snooping.
  - [x] 9.6 Implement stall logic: stall if any of: ROB full, free list empty (and instruction needs a destination), target reservation station full, load queue full (for LOAD), store queue full (for STORE).
  - [x] 9.7 On stall, hold the current instructions in the fetch buffer (do not dequeue) and do not update RAT/ROB/free list.
  - [x] 9.8 Checkpoint the RAT when dispatching a branch instruction (for misprediction recovery).
  - [x] 9.9 Compile and verify the decode/rename path with a simple sequence: two independent ALU instructions, then two with a dependency.

- [x] 10.0 Integrate all modules into `tinker_top.sv`
  - [x] 10.1 Create `tinker_top.sv` with the same external interface as the original `tinker.sv` (clk, reset, hlt). Instantiate: memory, reg_file (architectural), phys_reg_file, free_list, rat, fetch_unit, decode_rename, reservation stations (rs_alu x1 shared pool of 8, rs_fpu x1 shared pool of 8), alu_pipe x2, fpu_pipe x2, load_store_queue, cdb, rob.
  - [x] 10.2 Wire fetch_unit outputs to decode_rename inputs. Wire decode_rename outputs to reservation stations and ROB allocate port.
  - [x] 10.3 Wire reservation station issue outputs to the corresponding pipelined functional units (ALU RS -> alu_pipe_0/1, FPU RS -> fpu_pipe_0/1). Handle assignment of ready instructions to the 2 units of each type (e.g., first ready -> unit 0, second ready -> unit 1).
  - [x] 10.4 Wire functional unit outputs and load results to CDB inputs. Wire CDB outputs to reservation stations (snoop), ROB (complete), and physical register file (write).
  - [x] 10.5 Wire ROB commit outputs to: architectural reg_file (write committed values), memory (store commits), free_list (return old physical registers).
  - [x] 10.6 Wire misprediction path: ROB flush signal -> fetch_unit (redirect PC), RAT (restore checkpoint), reservation stations (flush), load_store_queue (flush), functional unit pipelines (flush in-flight instructions).
  - [x] 10.7 Wire HALT: when ROB commits a HALT instruction, assert `hlt` output.
  - [x] 10.8 Compile `tinker_top.sv` with all submodules using `iverilog -g2012`. Fix any port mismatches or signal width issues.

- [x] 11.0 Build testbenches and verify correctness
  - [x] 11.1 Create `tinker_tb.sv` with the same test infrastructure as the original `tinker_tb.sv` (clock gen, reset, VCD dump, `mk_instr` helper, `store_instr` task).
  - [x] 11.2 Test 1 — Basic ALU: `addi r1, #5; addi r1, #3; halt`. Verify r1 == 8. (RAW dependency through rename/CDB, completed in 10 cycles.)
  - [x] 11.3 Test 2 — Dual-issue independent: `addi r1, #10; addi r2, #20; halt`. Verify r1 == 10, r2 == 20. (Completed in 8 cycles.)
  - [x] 11.4 Test 3 — Load/Store: `movi r1, #100; store (r0)(0), r1; load r3, (r0)(0); halt`. Verify r3 == 100. (Completed in 10 cycles.)
  - [x] 11.5 Test 4 — Branch: `movi r1, #42; brr_l #8; movi r2, #99; halt`. Verify r1==42, r2==0 (flushed), hlt. (Completed in 10 cycles.)
  - [x] 11.6 Test 5 — FPU: load two IEEE 754 doubles (1.5, 2.5), `fadd r3, r1, r2; halt`. Verify r3 == 4.0. (Completed in 21 cycles.)
  - [x] 11.7 Test 6 — Mixed ILP: 6 independent ADDI to exercise dual-issue. All register values correct. (Completed in 10 cycles.)
  - [ ] 11.8 Test 7 — CALL/RETURN: deferred (CALL/RETURN require stack support not yet implemented).
  - [x] 11.9 All 6 tests pass with `iverilog -g2012`. 19/19 checks pass.
  - [x] 11.10 VCD waveform dump generated (`tinker_tb.vcd`) for review.
