# =========================================================
# Copyright (C) 2026  Daniel Halen
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# =========================================================
# builder2.py - Dedicated Bare-Metal Compiler for Fraqshift OS Kernel (NASM Output)
# builder2.py - Dedicated Bare-Metal Compiler for Fraqshift OS Kernel (NASM Output)
# builder2.py - Dedicated Bare-Metal Compiler for Fraqshift OS Kernel (NASM Output)

# builder2.py - Dedicated Bare-Metal Compiler for Fraqshift OS Kernel (NASM Output)

# builder2.py - Dedicated Bare-Metal Compiler for Fraqshift OS Kernel (NASM Output)
# builder2.py - Dedicated Bare-Metal Compiler for Fraqshift OS Kernel (NASM Output)
# builder2.py - Dedicated Bare-Metal Compiler for Fraqshift OS Kernel (NASM Output)
# builder2.py - Dedicated Bare-Metal Compiler for Fraqshift OS Kernel (NASM Output)
# builder2.py - Dedicated Bare-Metal Compiler for Fraqshift OS Kernel (NASM Output)
# builder2.py - Dedicated Bare-Metal Compiler for Fraqshift OS Kernel (NASM Output)
# builder2.py - Dedicated Bare-Metal Compiler for Fraqshift OS Kernel (NASM Output)
# builder2.py - Dedicated Bare-Metal Compiler for Fraqshift OS Kernel (NASM Output)

# builder2.py - Dedicated Bare-Metal Compiler for Fraqshift OS Kernel (NASM Output)
import os
import sys

print("--- FRAQSHIFT OS CORE COMPILER V6.3 (SUBROUTINE ISOLATION ENGINE) ---")

source_file = "main.fraq"
if not os.path.exists(source_file):
    print(f"Error: Could not find {source_file}")
    exit()

with open(source_file, "r", encoding="utf-8") as f:
    lines = f.readlines()

# --- 1. LEXER, PARSER & SYMBOL TABLE ---
compiled_assembly = ""
compiled_functions = ""  # CRITICAL FIX: Separate function stream to isolate them from boot flow
strings_data = []
current_string_index = 0

symbol_table = {}
stack_offset = 0

if_counter = 0
if_stack = []

loop_counter = 0
loop_stack = []

clear_counter = 0
in_function = False

# --- STAGE 1 BOOTLOADER: Read Kernel from disk & Switch to 64-bit ---
compiled_assembly += """BITS 16
org 0x7C00                  ; MBR entry address

start_bootloader:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00          ; Set up secure stack below bootloader

    ; --- Load Stage 2 Kernel from Hard Disk ---
    mov ah, 0x02            ; BIOS Read Sectors function
    mov al, 15              ; Load 15 sectors (7.5 KB of code space)
    mov ch, 0               ; Cylinder 0
    mov cl, 2               ; Start reading from sector 2 (right after MBR)
    mov dh, 0               ; Head 0
    mov bx, 0x7E00          ; Read kernel directly into memory right after bootloader
    int 0x13                ; Call BIOS disk service
    jc .disk_error          ; If carry flag set, disk read failed

    cli                     ; Disable interrupts for hardware switch

    ; --- Set up 64-bit Page Tables at a safe address (0x9000) ---
    mov edi, 0x9000
    mov cr3, edi
    xor eax, eax
    mov ecx, 4096
    rep stosd
    
    mov dword [0x9000], 0xA003
    mov dword [0xA000], 0xB003
    mov dword [0xB000], 0x0083  ; Identity map first 2MB

    ; --- Enable PAE ---
    mov eax, 10100000b
    mov cr4, eax

    ; --- Enable Long Mode ---
    mov ecx, 0xC0000080
    rdmsr
    or eax, 0x00000100
    wrmsr

    ; --- Enable Paging and Protected Mode ---
    mov eax, cr0
    or eax, 0x80000001
    mov cr0, eax

    ; --- Load GDT and jump to 64-bit Stage 2 Kernel ---
    lgdt [gdt_ptr]
    jmp 0x08:stage2_kernel

.disk_error:
    mov ah, 0x0E
    mov al, 'E'
    int 0x10                ; Print 'E' to show hardware disk failure
.halt_loader:
    hlt
    jmp .halt_loader

; --- MINIMALIST 64-BIT GLOBAL DESCRIPTOR TABLE (GDT) ---
align 8
gdt_start:
    dq 0x0000000000000000   ; Null Descriptor
gdt_code:
    dq 0x00209A0000000000   ; 64-bit Code Descriptor
gdt_data:
    dq 0x0000920000000000   ; 64-bit Data Descriptor
gdt_end:

gdt_ptr:
    dw gdt_end - gdt_start - 1
    dq gdt_start

times 510-($-$$) db 0       ; Pad Stage 1 to exactly 510 bytes
dw 0xAA55                   ; MBR Boot Signature for Sector 1

; ==============================================================================
; STAGE 2 KERNEL: Executed in pure 64-bit Long Mode (Frigjord från 512 bytes!)
; ==============================================================================
BITS 64

stage2_kernel:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov rdi, 0xB8000        ; Initialize screen pointer

kernel_main:
    push rbp
    mov rbp, rsp
"""

# --- PARSER LOOP ---
for line_num, line in enumerate(lines, 1):
    line = line.strip()
    if not line or line.startswith(";"):
        continue
        
        # --- ROUTE GENERATION BASED ON CONTEXT ---
    target_code = ""

    if line.startswith("data.string"):
        try:
            parts = line.split('"')
            raw_text = parts[1]
            strings_data.append((current_string_index, raw_text))
            current_string_index += 1
        except IndexError:
            print(f"Syntax Error on line {line_num}: Missing quotes in data.string!")
            exit()
            
    elif line == "sys.out":
        if not strings_data:
            print(f"Error on line {line_num}: sys.out called before data.string!")
            exit()
        idx, text = strings_data[-1]
        length = len(text.encode('utf-8'))
        target_code += f"""
        lea rsi, [rel msg_{idx}]
        mov rdi, 0xB8000
        mov rcx, {length}
    .vga_string_loop_{idx}:
        lodsb
        mov [rdi], al
        mov byte [rdi+1], 0x07
        add rdi, 2
        loop .vga_string_loop_{idx}
        """

    elif line.startswith("var "):
        try:
            parts = [p for p in line.split() if p]
            var_name = parts[1]
            eq_idx = parts.index("=")
            var_value = int(parts[eq_idx + 1])
            
            if var_name in symbol_table:
                print(f"SECURITY ERROR on line {line_num}: Variable '{var_name}' already declared!")
                exit()
            stack_offset += 8
            symbol_table[var_name] = stack_offset
            target_code += f"""
            mov rax, {var_value}
            mov [rbp - {stack_offset}], rax
            """
        except (IndexError, ValueError):
            print(f"Syntax Error on line {line_num}: Invalid variable declaration!")
            exit()

    elif line.startswith("var.array "):
        try:
            parts = [p for p in line.split() if p]
            declaration = parts[1]
            if "[" not in declaration or not declaration.endswith("]"):
                raise ValueError
            var_name = declaration.split("[")[0]
            array_size = int(declaration.split("[")[1].replace("]", ""))
            
            if var_name in symbol_table:
                print(f"SECURITY ERROR on line {line_num}: Identifier '{var_name}' already declared!")
                exit()
            total_bytes = array_size * 8
            stack_offset += total_bytes
            symbol_table[var_name] = stack_offset
            target_code += f"""
            sub rsp, {total_bytes}         ; Allocate space for array
            """
        except (IndexError, ValueError):
            print(f"Syntax Error on line {line_num}: Invalid array declaration!")
            exit()

    elif "=" in line and not line.startswith("var "):
        try:
            parts = [p for p in line.split() if p]
            eq_idx = parts.index("=")
            new_value = int(parts[eq_idx + 1])
            left_side = parts[0]

            if "[" in left_side and left_side.endswith("]"):
                var_name = left_side.split("[")[0]
                array_idx = int(left_side.split("[")[1].replace("]", ""))
                if var_name not in symbol_table:
                    exit()
                base_offset = symbol_table[var_name]
                element_offset = base_offset - (array_idx * 8)
                target_code += f"""
                mov rax, {new_value}
                mov [rbp - {element_offset}], rax
                """
            else:
                var_name = left_side
                if var_name not in symbol_table:
                    exit()
                offset = symbol_table[var_name]
                target_code += f"""
                mov rax, {new_value}
                mov [rbp - {offset}], rax
                """
        except (IndexError, ValueError):
            print(f"Syntax Error on line {line_num}: Invalid reassignment syntax!")
            exit()

    elif line.startswith("data.array "):
        try:
            parts = [p for p in line.split() if p]
            target = parts[1]
            var_name = target.split("[")[0]
            array_idx = int(target.split("[")[1].replace("]", ""))
            base_offset = symbol_table[var_name]
            element_offset = base_offset - (array_idx * 8)
            target_code += f"""
            mov rax, [rbp - {element_offset}]
            push rax
            """
        except (IndexError, ValueError):
            print(f"Syntax Error on line {line_num}: Invalid data.array format!")
            exit()

    elif line.startswith("func void "):
        try:
            parts = [p for p in line.split() if p]
            func_name = parts[2]
            compiled_functions += f"\n{func_name}:\n"
            in_function = True
            continue
        except IndexError:
            exit()

    elif line == "func_done":
        if not in_function:
            exit()
        compiled_functions += "\nret\n"
        in_function = False
        continue

    elif line.startswith("sys.call "):
        try:
            parts = [p for p in line.split() if p]
            func_name = parts[1]
            target_code += f"\ncall {func_name}\n"
        except IndexError:
            exit()

    elif line.startswith("data.var"):
        try:
            parts = [p for p in line.split() if p]
            var_name = parts[1]
            offset = symbol_table[var_name]
            target_code += f"""
            mov rax, [rbp - {offset}]
            push rax
            """
        except IndexError:
            exit()

    elif line.startswith("data.int"):
        try:
            parts = [p for p in line.split() if p]
            value = int(parts[1])
            target_code += f"""
            mov rax, {value}
            push rax
            """
        except (IndexError, ValueError):
            exit()

    elif line == "sys.flush_key":
        target_code += """
    .flush_loop:
        in al, 0x64
        test al, 0x01
        jz .flush_done
        in al, 0x60
        jmp .flush_loop
    .flush_done:
        """

    elif line == "sys.read_key":
        target_code += """
    .wait_for_key:
        in al, 0x64
        test al, 0x01
        jz .wait_for_key
        in al, 0x60
        movzx rax, al
        push rax
        """

    elif line == "sys.clear":
        clear_counter += 1
        target_code += f"""
        mov rdi, 0xB8000
        mov rcx, 2000
        mov ax, 0x0720
    .vga_clear_loop_{clear_counter}:
        mov [rdi], ax
        add rdi, 2
        loop .vga_clear_loop_{clear_counter}
        mov rdi, 0xB8000
        """

    elif line.startswith("sys.add"):
        try:
            parts = [p for p in line.split() if p]
            value = int(parts[1])
            target_code += f"\npop rax\nadd rax, {value}\npush rax\n"
        except (IndexError, ValueError):
            exit()

    elif line.startswith("sys.sub"):
        try:
            parts = [p for p in line.split() if p]
            value = int(parts[1])
            target_code += f"\npop rax\nsub rax, {value}\npush rax\n"
        except (IndexError, ValueError):
            exit()

    elif line.startswith("sys.mul"):
        try:
            parts = [p for p in line.split() if p]
            value = int(parts[1])
            target_code += f"\npop rax\nmov rbx, {value}\nimul rax, rbx\npush rax\n"
        except (IndexError, ValueError):
            exit()

    elif line.startswith("sys.div"):
        try:
            parts = [p for p in line.split() if p]
            value = int(parts[1])
            target_code += f"\npop rax\nmov rbx, {value}\nxor rdx, rdx\nidiv rbx\npush rax\n"
        except (IndexError, ValueError):
            exit()

    elif line.startswith("sys.cmp"):
        try:
            parts = [p for p in line.split() if p]
            value = int(parts[1])
            target_code += f"\npop rax\ncmp rax, {value}\n"
        except (IndexError, ValueError):
            exit()

    elif line == "sys.if_eq":
        if_counter += 1
        if_stack.append(if_counter)
        target_code += f"jne .if_end_{if_counter}\n"

    elif line == "sys.if_done":
        current_if = if_stack.pop()
        target_code += f".if_end_{current_if}:\n"

    elif line == "sys.loop":
        loop_counter += 1
        loop_stack.append(loop_counter)
        target_code += f"\npop rcx\nxor rbx, rbx\n.loop_start_{loop_counter}:\ncmp rbx, rcx\njge .loop_end_{loop_counter}\npush rcx\npush rbx\n"

    elif line == "sys.loop_end":
        current_loop = loop_stack.pop()
        target_code += f"\npop rbx\npop rcx\ninc rbx\njmp .loop_start_{current_loop}\n.loop_end_{current_loop}:\n"

    elif line == "sys.print_char":
        target_code += "\npop rax\nmov [rdi], al\nmov byte [rdi+1], 0x0A\nadd rdi, 2\n"

    elif line == "sys.print_int":
        target_code += """
        pop rax
        sub rsp, 32
        mov rcx, rsp
        add rcx, 32
        mov rbx, 10
    .convert_loop_os:
        xor rdx, rdx
        idiv rbx
        add dl, 0x30
        dec rcx
        mov [rcx], dl
        test rax, rax
        jnz .convert_loop_os
        mov rdi, 0xB8000
        mov rdx, rsp
        add rdx, 32
    .vga_print_loop:
        cmp rcx, rdx
        je .vga_print_done
        mov al, [rcx]
        mov [rdi], al
        mov byte [rdi+1], 0x0A
        add rdi, 2
        inc rcx
        jmp .vga_print_loop
    .vga_print_done:
        add rsp, 32
        """
    else:
        print(f"Syntax Error on line {line_num}: Unknown command '{line}'")
        exit()

    # Append to the right code section stream
    if in_function:
        compiled_functions += target_code
    else:
        compiled_assembly += target_code

# --- HARDWARE SYSTEM HALT LOOP ---
compiled_assembly += """
    mov rsp, rbp
    pop rbp
.kernel_halt:
    hlt
    jmp .kernel_halt
"""

# --- INJECT ALL SAFE SUBROUTINES AT THE ABSOLUTE BOTTOM ---
compiled_assembly += compiled_functions

# --- APPEND DATA SECTION FOR STRINGS & PAD TOTAL IMAGE ---
if strings_data:
    compiled_assembly += "\nsection .data\n"
    for idx, text in strings_data:
        compiled_assembly += f'msg_{idx}: db "{text}", 0\n'

compiled_assembly += """
section .pad
times 32768-($-$$) db 0
"""

output_asm_file = "kernel.asm"
with open(output_asm_file, "w", encoding="utf-8") as f:
    f.write(compiled_assembly)

print("=========================================================")
print(f"-> STEP 1 SUCCESSFUL: Generated Two-Stage '{output_asm_file}'")
print("=========================================================")

