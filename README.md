# Fraqshift

[![License: GPL v3](https://shields.io)](https://gnu.org)
[![Discord](https://shields.io)](https://discord.gg/t3wbbfYN5T)

Fraqshift is a high-performance, low-level systems programming language engineered to combine modern data syntax with bare-metal hardware control. It compiles code directly into native x86-64 machine instructions for a custom, standalone Operating System ecosystem.

## Project Milestone: 100% Self-Hosting Achieved! 

Fraqshift has officially completed its bootstrapping lifecycle and **broken free from Python, C, Windows, and Linux dependencies**. 

The entire compiler pipeline (Tokenizer → Symbol Table → Code Generator) now executes as an autonomous, single-pass machine-stream running entirely on native CPU transistors. The umbilical cord to Python has been cut for good, achieving absolute self-hosting supremacy inside the bare-metal Fraqshift OS.

## Key Features

* **Autonomous Self-Hosting Supremacy:** The compiler is written in Fraqshift, compiling its own source code directly inside the QEMU bare-metal sandbox.
* **Pure Bare-Metal Kernel Execution:** Generates flat binary files that boot directly on x86-64 hardware without an underlying OS layer.
* **Silicon-Level Control:** Multi-target architecture built to interface directly with custom VESA Linear Framebuffers, PS/2 keyboard/mouse buses, and legacy ATA drive ports.
* **Inline Hardware Interfacing:** Native support for 64-bit Assembly registers and high-speed RAM pointer manipulation (`*ptr = rax`) with zero-copy overhead.
* **Pure NASM Compilation Pipeline:** Leverages a local Netwide Assembler (NASM) engine for zero-dependency hardware binaries.

## Language Syntax (`main.fraq`)

Fraqshift uses clean data definitions paired with immediate hardware execution tokens and flag-safe logic:

```text
; ===================================================
; FRAQSHIFT OS - COMBINED THREE-BLOCK ENGINE TEST
; ===================================================

; 1. Prepare global RAM buffers for the text stream
var addr_one = 327680
*addr_one = 73              ; 'I'

; 2. Secure global variable registrations in the Symbol Table
var table_reg = 328000
*table_reg = 88             ; Variable 'X'

; 3. Execute the compiler pipeline safely in the CPU registers
sys.call run_compiler_pipeline

; 4. Fetch the resulting Token ID directly from the protected RBX register
data.reg rbx
sys.print_int
```

## Getting Started & Compiling

### Prerequisites
The standalone development environment requires **NASM (Netwide Assembler)** placed locally in the project directory, and **QEMU** installed to emulate the hardware sandbox. *No Python interpreter or external toolchains are required.*

### The Standalone Interactive Dev Loop
The automated environment is managed via an interactive, loop-stabilized execution matrix:

```bash
.\build_and_run.bat
```

The optimized automated workflow handles the entire lifecycle:
1. **Hardware Assembly:** Invokes local `nasm.exe` to package `kernel.asm` straight into a flat, production-ready binary (`fraqshift_kernel.bin`) embedded with the magic MBR boot sector signature (`0xAA55`).
2. **Sandbox Booting:** Instantly launches a standalone QEMU instance to execute your native code inside an isolated hardware environment.
3. **Interactive Control Loop:** Press **`[R]`** to instantly re-assemble and restart the environment, or **`[X]`** to securely close the session and clean active environment variables.

## Project Roadmap & Kisel-Evolution

Fraqshift eliminates legacy bloat and compilation layers through a clean, multi-stage bare-metal engineering blueprint.

- [x] **Phase 1-3: Bootstrap Compiler Base** — Core Python tokenization, raw 64-bit stack frame allocation, and basic x86-64 flat binary output.
- [x] **Phase 4-5: Hardware Engines & VGA** — Implementation of the silicon decision engine (`sys.if_eq`), text-streaming to VGA memory, and local automated NASM pipeline.
- [x] **Phase 6: Hardware Flow Control** — Deterministic loop blocks (`sys.loop`), PS/2 keyboard buffer flushing, and a robust multi-stage bootloader architecture.
- [x] **Phase 7: Memory Matrix & Subroutines** — Static 64-bit array allocation, dynamic element indexing, and bare-metal function blocks (`func void`) using native CPU calling conventions.
- [x] **Phase 8: Pointer Dereferencing & Registers** — Direct raw memory pointers, high-speed RAM streaming, and manual CPU register optimization mapping (`sys.reg`) to maximize execution speeds.
- [x] **Phase 9: Single-Pass Tokenizer & Flag-Safe Evaluation** — Raw memory character streaming (`data.peek`), direct register extractions (`data.reg rbx`), and flag-protected conditional matching blocks.
- [x] **Phase 10: Full Self-Hosting & Bootstrapping Compiler Supremacy** (COMPLETED)
    *   Expanded the tokenizer engine into a space/newline dynamic stream-splitter.
    *   Implemented the bare-metal Symbol Table inside global RAM (`328000`) to track offsets.
    *   Designed the final raw machine code emitter (`*output_ptr = rax`) utilizing standard x86-64 calling conventions.
    *   Successfully executed the historical bootstrapping sequence, allowing Fraqshift to compile and run on pure kisel without a single line of Python.
      
- [ ] **Phase 11: Human Interface & Cyberpunk HUD Desktop**  (ACTIVE)
    *   Transition the 64-bit Stage 2 Bootloader from legacy text-mode to an advanced VESA BIOS Extensions (VBE) linear framebuffer (640x480 @ High Color).
    *   Develop an ultra-low-overhead, hardware-accelerated Bitmap Font Engine utilizing native CPU register streaming and Font ROM bitmapping.
    *   **UPDATED DESIGN:** Implement a custom "Hacker HUD Control Center" workspace layout. Move the traditional desktop taskbar to a sleek, ergonomic Top Bar bounded by an electric neon-purple horizontal line.
    *   **UPDATED DESIGN:** Build a non-overlapping Tiling Split-Screen environment to prevent bare-metal drawing collision over the hardware background image. Dedicated left window space mapped for a lightweight web terminal, and right window block mapped for CLI execution.
    *   Implement an interactive klick-hitbox engine tracking PS/2 mouse deltas and click state flags (`r13b`) to allow fluid window repositioning.

- [ ] **Phase 12: Memory Matrix Isolation & Ring 3 Security**  (UPCOMING)
    *   Build out processor Model-Specific Registers (MSR) and safe 64-bit Paging boundary walls.
    *   Enforce hardware-level memory clipping, establishing a permanent partition between the secure Kernel Space and isolated application processes (Ring 3 User Mode) to stop execution-level crashes.

- [ ] **Phase 13: Storage Layer & ATA File System (FraqFS)**  (UPCOMING)
    *   Optimize the native IDE/ATA hard disk controller driver to allow direct sector data pipelining.
    *   Implement an light dynamic directory file allocation table to track, read, and write stored documents using real named addresses without raw sector referencing.

- [ ] **Phase 14: PCI-Bus Scanning & Intel e1000 Netstack**  (UPCOMING)
    *   Develop a bare-metal PCI-bus hardware scanner to discover and communicate with onboard peripherals.
    *   Write a native hardware driver for the emulated Intel e1000 Gigabit Ethernet network controller utilizing Memory-Mapped I/O (MMIO).
    *   Design a zero-copy, single-pass network stack managing ARP, IPv4/IPv6, UDP, and TCP protocols directly inside high-speed registers to execute remote text-parsing web connections.

## Project Issue Tracker (Active Defect Log)

*   **Issue #01: Window Dragging "Windows 95" Trail Feedback Loop**
    *   *Severity:* Medium | *Component:* VRAM Compositor
    *   *Description:* Rapid updates to RAM window coordinates during active PS/2 mouse tracking leave ghosting trail patches due to the execution latency of full ATA-drive disk-to-screen background re-streaming.
    *   *Target Fix:* Refactor loop to intercept real-time movement deltas with a lightweight wireframe boundary box, deferring the heavy disk-stream refresh until button release transitions.
*   **Issue #02: Taskbar Start Button Icon Corruption**
    *   *Severity:* Low | *Component:* Blit Engine
    *   *Description:* The circular cyber-bat raw `.bin` asset renders compressed or exhibits green/yellow pixel noise on the black taskbar due to a Little-Endian byte-order conflict and stream alignment row padding.
    *   *Target Fix:* Adjust byte-width specifications inside the font/icon asset compiler loop to match standard LFB channels.

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.
