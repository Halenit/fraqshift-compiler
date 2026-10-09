# Fraqshift

[![License: GPL v3](https://shields.io)](https://gnu.org)

Fraqshift is a high-performance, low-level systems programming language engineered to combine modern data syntax with bare-metal hardware control. It compiles code directly into native x86-64 machine instructions for a custom, standalone Operating System ecosystem.

## The Vision: Self-Hosting

Fraqshift is currently in its **bootstrap phase**. The compiler is temporarily written in Python (`builder2.py`) to build the initial language infrastructure. 

The ultimate goal of this project is to achieve **complete self-hosting**—meaning the final Fraqshift compiler will be written entirely in Fraqshift itself, running inside its own bare-metal OS and completely removing dependencies on Python, C, Windows, or Linux.

## Key Features

* **Pure Bare-Metal Kernel Execution:** Generates flat binary files that boot directly on x86-64 hardware without an underlying OS layer.
* **Silicon-Level Control:** Multi-target architecture built to interface directly with VGA video buffers (`0xB8000`) and PS/2 keyboard hardware ports.
* **Inline `matrix_asm`:** Native support for 64-bit Assembly instructions and high-speed memory streaming.
* **NASM Compilation Pipeline:** Leverages the industry-standard Netwide Assembler (NASM) for zero-dependency hardware binaries.

## Language Syntax (`main.fraq`)

Fraqshift uses clean data definitions paired with immediate hardware execution tokens:

```
; ===================================================
; FRAQSHIFT OS - BARE-METAL NASM CORE HARDWARE TEST
; ===================================================

; 1. Initialize and secure data on the stack
var base_value = 50

; 2. Execute arithmetic directly in the CPU (50 * 2 = 100)
data.var base_value
sys.mul 2

; 3. Core hardware decision engine test
sys.cmp 100
sys.if_eq
    data.string "FRAQSHIFT OS: Silicon decision engine is online via NASM!"
    sys.out
sys.if_done

; 4. Sequential flow control (Add 42 to stack and stream to VGA)
data.var base_value
sys.add 42
sys.print_int
```

## Getting Started & Compiling

### Prerequisites
The bootstrap compiler requires Python 3, **NASM (Netwide Assembler)** placed locally in the project directory, and **QEMU** installed to emulate the hardware sandbox.

### Compilation & Execution Pipeline
Instead of running manual commands, the build chain is fully automated via an interactive development loop:

```bash
.\build_and_run.bat
```

The automated script handles the entire lifecycle:
1. **Python Translation:** `builder2.py` maps variables and compiles `.fraq` streams into clean x86-64 Assembly text (`kernel.asm`).
2. **Hardware Assembly:** `nasm.exe` packages the assembly into a flat binary file (`fraqshift_kernel.bin`) injected with a magic boot sector signature (`0xAA55`).
3. **Sandbox Booting:** Launches QEMU to execute your native code inside an isolated hardware sandbox.

## Project Roadmap & Self-Hosting Strategy

To design a compiler that executes faster and cleaner than C/C++ and Python, Fraqshift eliminates legacy overhead (such as include-headers and virtual runtimes) through a 9-Phase bare-metal engineering blueprint.

- [x] **Phase 1-3: Bootstrap Compiler Base** — Core Python tokenization, raw 64-bit stack frame allocation, and basic x86-64 flat binary output.
- [x] **Phase 4-5: Hardware Engines & VGA** — Implementation of the silicon decision engine (`sys.if_eq`), text-streaming to VGA memory, and local automated NASM pipeline.
- [x] **Phase 6: Hardware Flow Control** — Deterministic loop blocks (`sys.loop`), PS/2 keyboard buffer flushing, and a robust multi-stage bootloader architecture.
- [x] **Phase 7 (Current): Memory Matrix & Subroutines** — Static 64-bit array allocation, dynamic element indexing, and bare-metal function blocks (`func void`) using native CPU calling conventions.
- [x] **Phase 8: Pointer Dereferencing & Registers** — Direct raw memory pointers, high-speed RAM streaming, and manual CPU register optimization mapping (`sys.reg`) to maximize execution speeds.
- [ ] **Phase 9: Single-Pass Tokenizer & Self-Hosting Execution** — Writing the final compilation engine inside Fraqshift itself. The compiler reads `main.fraq` using text-arrays, outputs pure machine code without python/linker dependencies, and achieves 100% self-hosting supremacy inside Fraqshift OS.


## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.
