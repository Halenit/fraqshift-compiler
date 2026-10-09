# Fraqshift Language Specification & Architecture (V6.0)

This document serves as the official technical specification for the **Fraqshift systems programming language**. It describes the core execution model, memory layout, register management, and hardware instructions for developers building software or expanding the bootstrap compiler (`builder2.py`).

---

## 1. Core Execution Model

Fraqshift is a pure **stack-based systems language** operating directly on x86-64 hardware in **64-bit Long Mode**. 
* **Zero Runtime Overhead:** There is no virtual machine, interpreter, or standard garbage collector.
* **Deterministic Stack:** Calculations are performed by pushing elements onto the CPU's hardware stack and invoking execution tokens that pop operands directly into CPU registers.

---

## 2. Memory Layout & Register Allocation

When the kernel initializes via the 64-bit trampoline, the stack frame is anchored to isolate variable scopes:

* `RBP` (Base Pointer): Anchors local variable allocations.
* `RSP` (Stack Pointer): Tracks the active execution/calculation stack.
* `RAX` & `RBX`: Reserved as high-speed primary hardware execution registers for arithmetic operations.
* `RDI` & `RSI`: Reserved for hardware streaming and memory interface operations (e.g., VGA buffer manipulation and matrix streaming).

### Named Variable Isolation
Named variables are declared with static initialization. Each 64-bit variable takes exactly **8 bytes** of space and is safely mapped below the base pointer:
```text
[RBP - 8]  -> First Declared Variable
[RBP - 16] -> Second Declared Variable
```

---

## 3. Instruction Set Reference

### 3.1 Data Management

#### `var [name] = [integer]`
Allocates a unique 8-byte slot on the hardware stack and initializes it with an immediate value.
* **Assembly mapping:** `mov qword [rbp - offset], value`

#### `data.var [name]`
Fetches the value stored in a variable's isolated stack slot and pushes it onto the calculation stack.
* **Assembly mapping:** `mov rax, [rbp - offset]` followed by `push rax`

#### `data.int [integer]`
Pushes a raw 64-bit immediate literal integer directly onto the calculation stack.
* **Assembly mapping:** `mov rax, value` followed by `push rax`

---

### 3.2 Arithmetic Tokens (Stack-Based)

All arithmetic tokens take an immediate integer operand, executing operations directly within CPU hardware registers before pushing results back onto the stack.

#### `sys.add [integer]`
Pops the top value from the calculation stack, adds the immediate integer, and pushes the sum back.
* **Assembly mapping:** `pop rax` -> `add rax, value` -> `push rax`

#### `sys.sub [integer]`
Pops the top value, subtracts the immediate integer, and pushes the result.
* **Assembly mapping:** `pop rax` -> `sub rax, value` -> `push rax`

#### `sys.mul [integer]`
Pops the top value, executes signed hardware multiplication (`imul`) with the immediate integer, and pushes the product.
* **Assembly mapping:** `pop rax` -> `mov rbx, value` -> `imul rax, rbx` -> `push rax`

#### `sys.div [integer]`
Pops the top value, clears `RDX` to prevent CPU faults, divides `RAX` by the immediate integer, and pushes the quotient. **Division by zero triggers a strict compile-time security error.**
* **Assembly mapping:** `pop rax` -> `mov rbx, value` -> `xor rdx, rdx` -> `idiv rbx` -> `push rax`

---

### 3.3 Hardware Decision Engine (Flow Control)

#### `sys.cmp [integer]`
Pops the latest calculation result from the stack and compares it with the immediate integer, setting the processor's hardware flags (`RFLAGS`).
* **Assembly mapping:** `pop rax` -> `cmp rax, value`

#### `sys.if_eq`
Defines the start of a conditional hardware block. If the previous comparison flag is **Not Equal**, the CPU skips directly to the end of the block.
* **Assembly mapping:** `jne .if_end_[id]`

#### `sys.if_done`
Marks the absolute structural end boundary of a conditional block.
* **Assembly mapping:** `.if_end_[id]:`

---

### 3.4 Hardware Graphics & Stream Interfacing

#### `data.string "[text]"`
Defines a static string stream. The compiler translates this directly into a series of `mov` instructions to optimize kisel-level execution.

#### `sys.out`
Streams the most recently declared string directly into the VGA text-buffer memory interface at address **`0xB8000`** with standard light-gray attributes.

#### `sys.print_int`
Pops a 64-bit integer from the stack, executes base-10 hardware division loops, converts the individual numbers to ASCII digits backwards into a safe stack array, and dumps the string to the VGA graphics terminal in **bright AI green**.

#### `sys.print_char`
Pops an ASCII byte value from the calculation stack and outputs a single character straight onto the active VGA text matrix cell.
