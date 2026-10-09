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
import os
import sys

print("--- FRAQSHIFT OS CORE COMPILER V6.2 (TWO-STAGE NASM ENGINE) ---")

source_file = "main.fraq"
if not os.path.exists(source_file):
    print(f"Error: Could not find {source_file}")
    exit()

with open(source_file, "r", encoding="utf-8") as f:
    lines = f.readlines()

# --- 1. LEXER, PARSER & SYMBOL TABLE ---
compiled_assembly = ""
strings_data = []
current_string_index = 0

# Symbol tables and tracking stacks for flow control
symbol_table = {}
stack_offset = 0  # Each new 64-bit variable takes 8 bytes of space

if_counter = 0
if_stack = []

loop_counter = 0
loop_stack = []

clear_counter = 0  # Track unique clear loops to prevent NASM definition errors

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

kernel_main:
    push rbp
    mov rbp, rsp
"""

# --- PARSER LOOP ---
for line_num, line in enumerate(lines, 1):
    line = line.strip()
    if not line or line.startswith(";"):
        continue
        
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
        compiled_assembly += f"""
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
            # Safe parsing regardless of token lengths or whitespace anomalies
            parts = [p for p in line.split() if p]
            var_name = parts[1]
            
            # Find the position of the '=' token dynamically
            eq_idx = parts.index("=")
            var_value = int(parts[eq_idx + 1])
            
            if var_name in symbol_table:
                print(f"SECURITY ERROR on line {line_num}: Variable '{var_name}' already declared!")
                exit()
            stack_offset += 8
            symbol_table[var_name] = stack_offset
            compiled_assembly += f"""
            mov rax, {var_value}
            mov [rbp - {stack_offset}], rax
            """
        except (IndexError, ValueError):
            print(f"Syntax Error on line {line_num}: Invalid variable declaration!")
            exit()

    elif line.startswith("data.var"):
        try:
            parts = [p for p in line.split() if p]
            var_name = parts[1]
            if var_name not in symbol_table:
                print(f"SECURITY ERROR on line {line_num}: Variable '{var_name}' not declared!")
                exit()
            offset = symbol_table[var_name]
            compiled_assembly += f"""
            mov rax, [rbp - {offset}]
            push rax
            """
        except IndexError:
            print(f"Syntax Error on line {line_num}: Missing variable name!")
            exit()

    elif line.startswith("data.int"):
        try:
            parts = [p for p in line.split() if p]
            value = int(parts[1])
            compiled_assembly += f"""
            mov rax, {value}
            push rax
            """
        except (IndexError, ValueError):
            print(f"Syntax Error on line {line_num}: 'data.int' requires an integer!")
            exit()

    # --- FLUSH KEYBOARD BUFFER (`sys.flush_key`) ---
    elif line == "sys.flush_key":
        compiled_assembly += """
    .flush_loop:
        in al, 0x64             ; Read PS/2 status register
        test al, 0x01           ; Check if data is present in buffer (bit 0)
        jz .flush_done          ; If bit 0 is empty, buffer is cleared!
        in al, 0x60             ; Data present? Read and drop it to clear port
        jmp .flush_loop         ; Keep looping until buffer is perfectly empty
    .flush_done:
        """

    # --- PS/2 KEYBOARD INTERFACE (`sys.read_key`) ---
    elif line == "sys.read_key":
        compiled_assembly += """
    .wait_for_key:
        in al, 0x64             ; Read hardware status port from PS2 controller
        test al, 0x01           ; Mask bit 0 (Output Buffer Full status)
        jz .wait_for_key        ; If bit is 0, no data is ready -> spin lock loop
        
        in al, 0x60             ; Data ready! Read raw scancode from dataport 0x60
        movzx rax, al           ; Zero-extend 8-bit scancode into 64-bit RAX register
        push rax                ; Save scancode securely on calculation stack
        """

    # --- VGA SCREEN REFRESH (`sys.clear`) ---
    elif line == "sys.clear":
        clear_counter += 1
        compiled_assembly += f"""
        mov rdi, 0xB8000        ; Base address of VGA text buffer
        mov rcx, 2000           ; A standard terminal screen has 80x25 = 2000 character cells
        mov ax, 0x0720          ; 0x20 = ASCII space character, 0x07 = Light gray attribute
    .vga_clear_loop_{clear_counter}:
        mov [rdi], ax           ; Clear current screen cell
        add rdi, 2              ; Move to next cell pointer
        loop .vga_clear_loop_{clear_counter}
        mov rdi, 0xB8000        ; Reset pointer back to top-left corner for future writing!
        """

        # --- ARITHMETIC OPERATIONS (STACK-BASED) ---
    elif line.startswith("sys.add"):
        try:
            parts = [p for p in line.split() if p]
            value = int(parts[1])
            compiled_assembly += f"""
            pop rax
            add rax, {value}
            push rax
            """
        except (IndexError, ValueError):
            print(f"Syntax Error on line {line_num}: 'sys.add' requires an integer!")
            exit()

    elif line.startswith("sys.sub"):
        try:
            parts = [p for p in line.split() if p]
            value = int(parts[1])
            compiled_assembly += f"""
            pop rax
            sub rax, {value}
            push rax
            """
        except (IndexError, ValueError):
            print(f"Syntax Error on line {line_num}: 'sys.sub' requires an integer!")
            exit()

    elif line.startswith("sys.mul"):
        try:
            parts = [p for p in line.split() if p]
            value = int(parts[1])
            compiled_assembly += f"""
            pop rax
            mov rbx, {value}
            imul rax, rbx
            push rax
            """
        except (IndexError, ValueError):
            print(f"Syntax Error on line {line_num}: 'sys.mul' requires an integer!")
            exit()

    elif line.startswith("sys.div"):
        try:
            parts = [p for p in line.split() if p]
            value = int(parts[1])
            if value == 0:
                print(f"SECURITY ERROR on line {line_num}: Division by 0 forbidden!")
                exit()
            compiled_assembly += f"""
            pop rax
            mov rbx, {value}
            xor rdx, rdx
            idiv rbx
            push rax
            """
        except (IndexError, ValueError):
            print(f"Syntax Error on line {line_num}: 'sys.div' requires an integer!")
            exit()

    elif line.startswith("sys.cmp"):
        try:
            parts = [p for p in line.split() if p]
            value = int(parts[1])
            compiled_assembly += f"""
            pop rax
            cmp rax, {value}
            """
        except (IndexError, ValueError):
            print(f"Syntax Error on line {line_num}: 'sys.cmp' requires an integer!")
            exit()

    elif line == "sys.if_eq":
        if_counter += 1
        if_stack.append(if_counter)
        compiled_assembly += f"jne .if_end_{if_counter}\n"

    elif line == "sys.if_done":
        if not if_stack:
            print(f"SECURITY ERROR on line {line_num}: Missing matching if statement!")
            exit()
        current_if = if_stack.pop()
        compiled_assembly += f".if_end_{current_if}:\n"

    elif line == "sys.loop":
        loop_counter += 1
        loop_stack.append(loop_counter)
        compiled_assembly += f"""
        pop rcx
        xor rbx, rbx
    .loop_start_{loop_counter}:
        cmp rbx, rcx
        jge .loop_end_{loop_counter}
        push rcx
        push rbx
        """

    elif line == "sys.loop_end":
        if not loop_stack:
            print(f"SECURITY ERROR on line {line_num}: Missing matching sys.loop!")
            exit()
        current_loop = loop_stack.pop()
        compiled_assembly += f"""
        pop rbx
        pop rcx
        inc rbx
        jmp .loop_start_{current_loop}
    .loop_end_{current_loop}:
        """

    elif line == "sys.print_char":
        compiled_assembly += """
        pop rax                 ; Fetch ASCII character from stack
        mov [rdi], al           ; Write character directly to current tracked VGA pointer
        mov byte [rdi+1], 0x0A  ; Set attribute to bright AI green color
        add rdi, 2              ; CRITICAL FIX: Advance tracking pointer 2 bytes forward!
        """


    elif line == "sys.print_int":
        compiled_assembly += """
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

# --- HARDWARE SYSTEM HALT LOOP ---
compiled_assembly += """
    mov rsp, rbp
    pop rbp
.kernel_halt:
    hlt
    jmp .kernel_halt
"""

# --- APPEND DATA SECTION FOR STRINGS & PAD TOTAL IMAGE ---
if strings_data:
    compiled_assembly += "\nsection .data\n"
    for idx, text in strings_data:
        compiled_assembly += f'msg_{idx}: db "{text}", 0\n'

# Pad the final binary image to exactly 32 KB (64 sectors)
compiled_assembly += """
section .pad
times 32768-($-$$) db 0
"""

# --- 2. EXPORT RAW ASSEMBLER TEXT FILE ---
output_asm_file = "kernel.asm"
with open(output_asm_file, "w", encoding="utf-8") as f:
    f.write(compiled_assembly)

print("=========================================================")
print(f"-> STEP 1 SUCCESSFUL: Generated Two-Stage '{output_asm_file}'")
print("=========================================================")
