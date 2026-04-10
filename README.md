# RISC-V RV32I Multi-Cycle Processor in Verilog

## Overview
This repository contains a fully functional, multi-cycle Verilog implementation of the **RISC-V RV32I Base Integer Instruction Set Architecture (ISA)**. 

Built entirely from scratch, this processor was designed with a focus on precise memory handling, deterministic execution, and realistic hardware constraints. Unlike basic single-cycle educational cores, this processor does not rely on internal, instantly accessible instruction/data arrays. Instead, it interfaces with a unified, external memory system using a strict asynchronous handshake protocol (`mem_rbusy` and `mem_wbusy`), accurately simulating the latencies found in real-world memory controllers and system buses.

## Key Architectural Features
* **Core Architecture:** 32-bit RISC-V (RV32I Base Integer Instruction Set).
* **Execution Model:** Multi-cycle Finite State Machine (FSM). The processor dynamically pauses execution based on memory readiness, ensuring data integrity without the need for strict clock-cycle counting.
* **Unified Memory Interface:** A single external memory bus handles both instruction fetching and data load/stores (Von Neumann architecture style from the processor's outward perspective).
* **Robust Alignment Handling:** Safely handles word-aligned loads and stores using dynamic bitwise masking and alignment logic, preventing unaligned memory access faults.
* **Signed Context Isolation:** Explicit separation of signed and unsigned evaluation contexts in the ALU to guarantee correct Arithmetic Right Shifts (`SRA`/`SRAI`) and signed branch comparisons.

---

## Supported Instruction Set Architecture (ISA)
This processor successfully decodes and executes the complete RV32I base integer set (excluding environment/system calls `ecall` and `ebreak`):

### 1. R-Type (Register-to-Register)
* **Arithmetic:** `ADD`, `SUB`
* **Logical:** `XOR`, `OR`, `AND`
* **Shifts:** `SLL` (Shift Left Logical), `SRL` (Shift Right Logical), `SRA` (Shift Right Arithmetic)
* **Comparisons:** `SLT` (Set Less Than), `SLTU` (Set Less Than Unsigned)

### 2. I-Type (Immediates)
* **Arithmetic:** `ADDI`
* **Logical:** `XORI`, `ORI`, `ANDI`
* **Shifts:** `SLLI`, `SRLI`, `SRAI`
* **Comparisons:** `SLTI`, `SLTIU`
* **Loads:** `LB` (Load Byte), `LH` (Load Halfword), `LW` (Load Word), `LBU` (Load Byte Unsigned), `LHU` (Load Halfword Unsigned)
* **Jumps:** `JALR` (Jump and Link Register)

### 3. S-Type (Stores)
* `SB` (Store Byte), `SH` (Store Half), `SW` (Store Word)

### 4. B-Type (Branches)
* `BEQ` (Equal), `BNE` (Not Equal), `BLT` (Less Than), `BGE` (Greater Than or Equal), `BLTU` (Less Than Unsigned), `BGEU` (Greater Than or Equal Unsigned)

### 5. U-Type (Upper Immediates)
* `LUI` (Load Upper Immediate), `AUIPC` (Add Upper Immediate to PC)

### 6. J-Type (Jumps)
* `JAL` (Jump and Link)

---

## Hardware Interface & I/O
The top-level module relies on a strict interface design to guarantee compatibility with external automated testbenches.

    module riscv_processor(
        input             clk,
        output reg [31:0] mem_addr,    // 32-bit address bus
        output reg [31:0] mem_wdata,   // 32-bit data to be written
        output reg [ 3:0] mem_wmask,   // 4-bit write mask (1 bit per byte)
        input      [31:0] mem_rdata,   // 32-bit input line for data/instructions
        output reg        mem_rstrb,   // Read strobe (active high to initiate read)
        input             mem_rbusy,   // Handshake: memory is currently fetching data
        input             mem_wbusy,   // Handshake: memory is currently writing data
        input             reset        // Active-high reset
    );

### Signal Details:
* **`mem_wmask`**: Allows byte-level writing. E.g., `4'b0001` writes to the lowest byte, `4'b1111` writes a full 32-bit word.
* **`mem_rstrb`**: The CPU asserts this high to request data at `mem_addr`.
* **`mem_rbusy` / `mem_wbusy`**: The memory asserts these high to tell the CPU to wait. The CPU will freeze its state machine until these signals drop to `0`, ensuring safe asynchronous timing.

---

## Finite State Machine (FSM) Design
To handle memory latency, the processor is governed by a 5-state multi-cycle FSM:

1. **`STATE_FETCH_REQ`**: The CPU outputs the Program Counter (`pc`) to `mem_addr` and asserts `mem_rstrb`.
2. **`STATE_FETCH_WAIT`**: The CPU idles. Once `mem_rbusy` drops to `0`, it latches the incoming `mem_rdata` into the Instruction Register.
3. **`STATE_EXECUTE`**: The core of the CPU. It decodes the instruction, evaluates branch conditions, processes ALU operations, and writes back to the register file. If the instruction is a Load or Store, it transitions to a memory wait state. Otherwise, it updates the PC and loops back to fetch.
4. **`STATE_MEM_R_WAIT` (Loads)**: The CPU waits for the external memory to retrieve data. Upon completion, it formats the data (sign/zero extending bytes or halfwords) and writes it to the destination register.
5. **`STATE_MEM_W_WAIT` (Stores)**: The CPU holds the `mem_wmask` and `mem_wdata` steady until the memory drops `mem_wbusy`, confirming a successful write.

---

## Simulation & Verification
This repository includes a highly rigorous, self-checking testbench (`tb_riscv_processor.v`).

### The Testbench Architecture
* **Memory Controller Simulation:** The testbench implements a dynamic, combinational memory controller that intentionally introduces cycle delays to strictly test the FSM's adherence to `rbusy`/`wbusy` handshakes. 
* **Mini-Assembler:** Instead of loading an external hex file, the testbench features custom Verilog `function` calls that encode human-readable assembly variables directly into RV32I machine code during initialization.
* **Automated Checking:** The testbench runs a predefined suite of instructions testing edge cases (signed vs. unsigned branch logic, negative arithmetic shifts, word alignment, and jumping over instructions). At the end of execution, it dumps the final register file states and automatically asserts a `PASS/FAIL` based on expected integer results.

### How to Run Locally
You will need a Verilog compiler/simulator such as Icarus Verilog.

**1. Clone the repository:**
```bash
git clone https://github.com/svm168/RV32I_Processor_Design_verilog_project.git
```

**2. Compile the design and testbench:**
```bash
iverilog -o output_riscv_processor design_riscv_processor.v tb_riscv_processor.v
```

**3. Run the simulation:**
```bash
vvp output_riscv_processor
```

**Expected Output:**
If everything compiles successfully, the terminal will output the state of all tested registers (`x1` through `x13`), along with their expected values, and conclude with:

    ====================================================
    ALL TESTS PASSED
    ====================================================
Otherwise:

    ====================================================
    FAILED
    ====================================================

## Unexpected Learning
During development, explicit care was taken to address Verilog's handling of the ternary operator (`? :`) in the context of signed arithmetic. By default, if any branch of a Verilog ternary operator is unsigned, the compiler downgrades the entire expression to unsigned. This processor utilizes isolated `if-else` blocks for arithmetic shifts (`>>>`) to ensure the compiler maintains the sign bit, accurately executing instructions like `SRA` and `SRAI` without logical shift downgrade errors.