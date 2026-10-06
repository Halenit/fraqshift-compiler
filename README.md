# Fraqshift

[![License: GPL v3](https://shields.io)](https://gnu.org)

Fraqshift is a high-performance, low-level systems programming language engineered to combine modern data syntax with bare-metal hardware control. It compiles code directly into native x86-64 machine instructions without any external linker dependencies.

##    The Vision: Self-Hosting

Fraqshift is currently in its **bootstrap phase**. The compiler is temporarily written in Python (`fraq_builder.py`) to build the initial language infrastructure. 

The ultimate goal of this project is to achieve **complete self-hosting**—meaning the final Fraqshift compiler will be written entirely in Fraqshift itself, completely removing the dependency on Python, C, or C++.

##    Key Features

* **Zero-Dependency Binaries:** Generates standalone executable files directly via custom binary structure injection.
* **Direct Hardware Control:** Multi-target compiler built to support both desktop applications and direct bare-metal hardware interfacing.
* **Inline `matrix_asm`:** Native support for 64-bit Assembly instructions and high-speed memory streaming.

##    Language Syntax (`main.fraq`)

Fraqshift uses clean data definitions paired with immediate hardware execution tokens:

```text
; --- High-level stream mapping ---
var kisel = 200
var motor = 58

data.var kisel
sys.sub 100       ; 200 - 100 = 100

data.var motor
sys.add 42        ; 58 + 42 = 100

; Combine and print the result
sys.add 100       ; 100 + 100 = 200
sys.print_int     ; Prints 200 to the screen
```

##   Getting Started & Compiling

### Prerequisites
The current bootstrap compiler requires Python 3 and the `keystone-engine` library.

```bash
pip install keystone-engine
```

### Compilation Pipeline
1. Create your source code file named `main.fraq`.
2. Run the compiler script to generate a native executable:

```bash
python fraq_builder.py --target windows
```

The compiler will automatically clean comments, handle stack-frame alignment, map variables, and output a fully executable binary.

##    Project Roadmap

- [x] **Phase 1-3:** Bootstrap compiler infrastructure, binary PE injection, and variable stack allocation.
- [x] **Phase 4-5:** Hardware decision engine (If-satser) and PS/2 keyboard polling drivers.
- [ ] **Phase 6 (Next):** Implement loop blocks (`sys.loop`) for repetitive execution.
- [ ] **Phase 7:** Dynamic variable reassignment and memory pointers (Arrays).
- [ ] **Phase 8:** Self-hosting transition—writing the compiler inside Fraqshift.

##    License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.
