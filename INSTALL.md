# Installation & Environment Guide

This document explains how to set up the local development environment required to compile and run the **Fraqshift OS Kernel**. Since Fraqshift executes directly on bare-metal x86-64 hardware, the pipeline requires specific cross-compilation assembly tools and hardware virtualization sandbox emulators.

---

## Prerequisites

Before building the kernel, ensure you have the following software infrastructure installed on your host system:

### 1. QEMU (Processor Emulator)
QEMU acts as our secure standalone hardware sandbox to execute the compiled bootable kernel binary directly on emulated CPU transistors.
* Download and run the official installer from [qemu.org](https://qemu.org).
* The automated build system expects the QEMU executable to be installed at its default Windows 64-bit location:  
  `C:\Program Files\qemu\qemu-system-x86_64.exe`

---

## Local Compiler Configuration

To prevent issues with Windows environment variable paths and enforce a strict zero-dependency infrastructure, **NASM (Netwide Assembler)** must be placed locally inside your active project root directory.

1. Download the latest official stable release of NASM for Windows (**Win64 ZIP** file package) from [nasm.us](https://nasm.us).
2. Extract the downloaded `.zip` file archive.
3. Locate the file named exactly **`nasm.exe`** and copy it.
4. Paste `nasm.exe` directly into your main Fraqshift project root directory.

Your unified project folder structure must look like this:
```text
Fraqshift/
├── nasm.exe                # Local Netwide Assembler Binary (Must be here!)
├── kernel.asm              # Your Core 64-bit Assembly Kernel Source
├── build_and_run.bat       # Interactive Environment Build Script
├── README.md               # Main Architecture Documentation
└── installation.md         # Environment Guide
```

---

## Compiling & Running Fraqshift

You do not need to type long terminal commands or configure manual linker scripts. The entire environment lifecycle is fully automated using the interactive developer script loop.

1. Open your terminal terminal in the project directory (e.g., inside VS Code).
2. Execute the automated batch file:
   ```bash
   .\build_and_run.bat
   ```

### What happens behind the scenes:
* **Step 1:** The local `nasm.exe` engine processes `kernel.asm` directly into flat, raw machine code instructions (`fraqshift_kernel.bin`) and injects the mandatory Master Boot Record signature (`0xAA55`) at Sector 0.
* **Step 2:** QEMU launches the sandbox virtual machine, shifts the emulated x86-64 CPU into **64-bit Long Mode**, and executes your kernel live on the silicon level.

### Interactive Loop Control:
Once you close the active QEMU graphics emulator screen, the local terminal will prompt you with the following interactive hardware choices:
* Press **`[R]`** to instantly re-assemble the kernel code and reboot the sandbox (ideal for rapid bare-metal development).
* Press **`[X]`** to securely close the emulation session and clean active environment variables.
