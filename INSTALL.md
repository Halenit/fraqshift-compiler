# Installation & Environment Setup Guide

This document explains how to set up the development environment required to compile and run the **Fraqshift OS Kernel**. Since Fraqshift executes directly on bare-metal x86-64 hardware, the pipeline requires specific cross-compilation and emulation tools.

---

## Prerequisites

Before building the kernel, ensure you have the following software installed on your host system:

### 1. Python 3
The bootstrap compiler (`builder2.py`) is written in Python.
* Download and install the latest version from [python.org](https://python.org).
* **Important:** Ensure you check the box that says **"Add Python to PATH"** during setup.

### 2. QEMU (Processor Emulator)
QEMU acts as our secure hardware sandbox to execute the compiled bootable kernel.
* Download and run the installer from [qemu.org](https://qemu.org).
* The automated build system expects QEMU to be installed at its default 64-bit location:  
  `C:\Program Files\qemu\qemu-system-x86_64.exe`

---

## Local Compiler Setup

To prevent issues with Windows environment paths and ensure zero-dependency building, **NASM (Netwide Assembler)** must be placed locally inside your project folder.

1. Download the latest official stable release of NASM for Windows (**Win64 ZIP** file) from [nasm.us](https://nasm.us).
2. Extract the downloaded `.zip` file.
3. Locate the file named **`nasm.exe`** and copy it.
4. Paste `nasm.exe` directly into your Fraqshift project root directory (the same folder containing `builder2.py`).

Your project folder structure should look like this:
```text
Fraqshift/
├── builder2.py             # Python Bootstrap Compiler (V6.0)
├── nasm.exe                # Local Netwide Assembler Binary (Must be here!)
├── main.fraq               # Your Fraqshift Source Code
├── build_and_run.bat       # Interactive Build Script
└── README.md               # Main Documentation
```

---

## Compiling & Running Fraqshift

You do not need to type long terminal commands manually. The entire lifecycle is fully automated using the interactive developer script.

1. Open your terminal in the project directory (e.g., inside VS Code).
2. Execute the automated batch file:
   ```bash
   .\build_and_run.bat
   ```

### What happens behind the scenes:
* **Step 1:** Python scans `main.fraq` and generates a clean, structured x86-64 assembly text file named `kernel.asm`.
* **Step 2:** The local `nasm.exe` processes `kernel.asm` into raw machine instructions (`fraqshift_kernel.bin`) and injects the mandatory Master Boot Record signature (`0xAA55`).
* **Step 3:** QEMU launches, shifts the virtual CPU into **64-bit Long Mode**, and executes your kernel live on the silicon level.

### Interactive Loop:
Once you close the QEMU window, the terminal will prompt you:
* Press **`R`** to automatically recompile and reboot (ideal for rapid development).
* Press **`X`** to safely close the terminal.
