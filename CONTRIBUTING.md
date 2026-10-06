# Contributing to Fraqshift

First off, thank you for taking the time to contribute!

Fraqshift is an open-source, bare-metal systems programming language licensed under the **GPL v3**. The project is currently in its bootstrap phase, moving from a Python-based cross-compiler towards complete self-hosting inside its own standalone 64-bit Operating System.

We welcome contributions from compiler enthusiasts, OS developers, and anyone passionate about low-level programming.

---

## Code of Conduct

By participating in this project, you agree to maintain a helpful, respectful, and collaborative environment. Be welcoming to developers of all skill levels—we are all learning together.

## How Can I Contribute?

### 1. Reporting Bugs & Proposing Features
* If you find a bug or have an idea for a new language feature:
* Check the **Issues** tab to ensure it hasn't already been reported.
* Open a new Issue describing the problem or feature request clearly.
* For bugs, include steps to reproduce the issue along with your `main.fraq` source code.

### 2. Working on Issues
Look for issues labeled **`good first issue`** or **`help wanted`**. These are great starting points designed to get you familiar with the architecture.

### 3. Submitting a Pull Request (PR)
When you are ready to contribute code:
1. **Fork the Repository:** Create your own copy of the Fraqshift repo.
2. **Create a Branch:** Use a descriptive name for your feature branch (e.g., `feature/sys-loop` or `bugfix/stack-offset`).
3. **Write Clean Code:** Ensure all code comments and terminal output messages are written in **English**.
4. **Test Your Changes:** Verify that your code compiles and executes successfully using the automated dev loop (`.\build_and_run.bat`) inside QEMU.
5. **Open a PR:** Submit your pull request against the `main` branch of the official repository. Provide a detailed summary of your changes.

---

## Coding Standards & Architecture

To keep the codebase maintainable during the bootstrap phase, please adhere to these core architectural guidelines:

* **Pure ASCII Assembly:** All generated code appended to `kernel.asm` must utilize native x86-64 NASM syntax. Strictly avoid linker-dependent directives (like `.ascii` or `.byte`) that break flat-binary raw hardware streams.
* **Silicon Isolation:** Every named variable must be strictly separated and mapped safely onto the hardware stack frame using deterministic stack offsets (`[rbp - offset]`).
* **Power Efficiency:** Never leave the CPU floating at the end of execution. Always ensure final code blocks terminate into a secure hardware sleep state (`hlt` loop).

## Questions?

If you have questions about the roadmap or need help understanding the 64-bit Long Mode initialization trampoline, feel free to open a discussion issue. We are more than happy to help you get started!
