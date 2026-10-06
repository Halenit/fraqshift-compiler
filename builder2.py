# builder2.py - Dedicated Bare-Metal Compiler for Fraqshift OS Kernel (NASM Output)
import os
import sys

print("--- FRAQSHIFT OS CORE COMPILER V6.0 (NASM ENGINE) ---")

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

# Symbol table for tracking named variables on the hardware stack
symbol_table = {}
stack_offset = 0  # Each new 64-bit variable takes 8 bytes of space
if_counter = 0
if_stack = []

# --- INITIAL BOILERPLATE (Setting up pure x86-64 NASM environment) ---
compiled_assembly += """BITS 16                     ; CPU starts in 16-bit Real Mode after BIOS
org 0x7C00                  ; Standard MBR bootloader entry address

start_boot:
    cli                     ; Disable interrupts during hardware switch
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00          ; Set up temporary safe real-mode stack

    ; --- Enable PAE and Page Tables for 64-bit Mode ---
    mov eax, 10100000b      ; Enable PAE (bit 5) and PGE (bit 7)
    mov cr4, eax

    ; --- Set up minimalist 64-bit Page Tables at a safe address ---
    mov edi, 0x1000         ; Page directory table base address
    mov cr3, edi            ; Point CR3 to entry page table
    xor eax, eax
    mov ecx, 4096
    rep stosd               ; Zero out memory space for page tables
    
    ; Identity map the first 2 megabytes of hardware RAM
    mov dword [0x1000], 0x2003  ; PML4 points to PDPT
    mov dword [0x2000], 0x3003  ; PDPT points to PDT
    mov dword [0x3000], 0x0083  ; PDT entry maps first 2MB page directly

    ; --- Enable Long Mode in EFER (Extended Feature Enable Register) ---
    mov ecx, 0xC0000080     ; EFER MSR register ID
    rdmsr
    or eax, 0x00000100      ; Set LME (Long Mode Enable bit 8)
    wrmsr

    ; --- Enable Paging and enter 32-bit Compatibility / 64-bit Long Mode ---
    mov eax, cr0
    or eax, 0x80000001      ; Enable Paging (PG bit 31) and Protected Mode (PE bit 0)
    mov cr0, eax

    ; --- Load a minimalist 64-bit Global Descriptor Table (GDT) ---
    lgdt [gdt_ptr]
    jmp 0x08:.entry_64      ; Patched: Clean hardware jump to 64-bit mode

BITS 64                     ; PROCESSOR IS NOW IN PURE 64-BIT LONG MODE!
.entry_64:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

kernel_main:
    push rbp                    ; Save previous base pointer
    mov rbp, rsp                ; Set up memory anchor for local variables
"""



# --- PARSER LOOP ---
for line_num, line in enumerate(lines, 1):
    line = line.strip()
    
    # Ignore empty lines and comments completely
    if not line or line.startswith(";"):
        continue
        
    # --- STRING HANDLING (`data.string`) ---
    if line.startswith("data.string"):
        try:
            parts = line.split('"')
            raw_text = parts[1]
            
            # Save string text to be appended at the end of the ASM file
            strings_data.append((current_string_index, raw_text))
            current_string_index += 1
        except IndexError:
            print(f"Syntax Error on line {line_num}: Missing quotes in data.string!")
            exit()
            
    # --- STRING OUTPUT DIRECT TO VGA (`sys.out`) ---
    elif line == "sys.out":
        if not strings_data:
            print(f"Error on line {line_num}: sys.out called before data.string!")
            exit()
            
        idx, text = strings_data[-1]
        length = len(text.encode('utf-8'))
        
        # Clean, native NASM instructions using relative addressing (rel)
        compiled_assembly += f"""
        lea rsi, [rel msg_{idx}] ; Load text address safely via NASM RIP-relative
        mov rdi, 0xB8000        ; RDI = VGA text-buffer base address
        mov rcx, {length}         ; Character count to print
    .vga_string_loop_{idx}:
        lodsb                   ; Load byte from RSI into AL, increment RSI
        mov [rdi], al           ; Write character directly to VGA video memory
        mov byte [rdi+1], 0x07  ; Standard color attribute (Light gray on black)
        add rdi, 2              ; Move VGA screen pointer 2 bytes forward
        loop .vga_string_loop_{idx}
        """

    # --- DECLARE NAMED VARIABLE (`var x = 5`) ---
    elif line.startswith("var "):
        try:
            parts = line.split()
            var_name = parts[1]
            if parts[2] != "=":
                raise ValueError
            var_value = int(parts[3])
            
            if var_name in symbol_table:
                print(f"SECURITY ERROR on line {line_num}: Variable '{var_name}' is already declared!")
                exit()
                
            stack_offset += 8
            symbol_table[var_name] = stack_offset
            
            compiled_assembly += f"""
            mov rax, {var_value}        ; Load literal value to CPU register
            mov [rbp - {stack_offset}], rax ; Save to unique isolated hardware stack slot
            """
        except (IndexError, ValueError):
            print(f"Syntax Error on line {line_num}: Invalid variable declaration! Format: var x = 5")
            exit()

    # --- LOAD VARIABLE TO CALCULATION STACK (`data.var x`) ---
    elif line.startswith("data.var"):
        try:
            parts = line.split()
            var_name = parts[1]
            
            if var_name not in symbol_table:
                print(f"SECURITY ERROR on line {line_num}: Variable '{var_name}' is not declared!")
                exit()
                
            offset = symbol_table[var_name]
            compiled_assembly += f"""
            mov rax, [rbp - {offset}] ; Fetch value from safe hardware memory location
            push rax                ; Push onto calculation stack for execution
            """
        except IndexError:
            print(f"Syntax Error on line {line_num}: You must specify a variable name!")
            exit()

    # --- PUSH DIRECT INTEGER (`data.int 10`) ---
    elif line.startswith("data.int"):
        try:
            parts = line.split()
            value = int(parts[1])
            compiled_assembly += f"""
            mov rax, {value}
            push rax
            """
        except (IndexError, ValueError):
            print(f"Syntax Error on line {line_num}: 'data.int' requires a valid integer!")
            exit()

    # --- ARITHMETIC OPERATIONS (STACK-BASED) ---
    elif line.startswith("sys.add"):
        try:
            parts = line.split()
            value = int(parts[1])
            compiled_assembly += f"""
            pop rax                 ; Fetch latest value from stack
            add rax, {value}        ; Execute addition directly in CPU
            push rax                ; Save back onto calculation stack
            """
        except (IndexError, ValueError):
            print(f"Syntax Error on line {line_num}: 'sys.add' requires an integer!")
            exit()

    elif line.startswith("sys.sub"):
        try:
            parts = line.split()
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
            parts = line.split()
            value = int(parts[1])
            compiled_assembly += f"""
            pop rax
            mov rbx, {value}
            imul rax, rbx           ; Signed multiplication
            push rax
            """
        except (IndexError, ValueError):
            print(f"Syntax Error on line {line_num}: 'sys.mul' requires an integer!")
            exit()

    elif line.startswith("sys.div"):
        try:
            parts = line.split()
            value = int(parts[1])
            if value == 0:
                print(f"SECURITY ERROR on line {line_num}: Division by 0 is forbidden on silicon level!")
                exit()
            compiled_assembly += f"""
            pop rax
            mov rbx, {value}
            xor rdx, rdx            ; Clear RDX for division hardware safety
            idiv rbx                ; Divide RAX by RBX, quotient stored in RAX
            push rax
            """
        except (IndexError, ValueError):
            print(f"Syntax Error on line {line_num}: 'sys.div' requires an integer!")
            exit()

    # --- HARDWARE DECISION ENGINE (IF STATEMENTS) ---
    elif line.startswith("sys.cmp"):
        try:
            parts = line.split()
            value = int(parts[1])
            compiled_assembly += f"""
            pop rax                 ; Fetch last result from stack
            cmp rax, {value}        ; Compare register with value (Sets CPU flags)
            """
        except (IndexError, ValueError):
            print(f"Syntax Error on line {line_num}: 'sys.cmp' requires a valid integer!")
            exit()

    elif line == "sys.if_eq":
        if_counter += 1
        if_stack.append(if_counter)
        compiled_assembly += f"""
        jne .if_end_{if_counter}   ; Jump if Not Equal directly to end of block
        """

    elif line == "sys.if_done":
        if not if_stack:
            print(f"SECURITY ERROR on line {line_num}: 'sys.if_done' found without a matching if statement!")
            exit()
        current_if = if_stack.pop()
        compiled_assembly += f"""
        .if_end_{current_if}:
        """

    # --- PS/2 KEYBOARD INTERFACE ---
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

        # --- VGA CHARACTER AND INTEGER OUTPUT ---
    elif line == "sys.print_char":
        compiled_assembly += """
        pop rax                 ; Fetch ASCII character from stack
        mov rdi, 0xB8000        ; Standard VGA text memory base address
        mov [rdi], al           ; Natural, clean NASM memory instruction
        mov byte [rdi+1], 0x0A  ; Set attribute to bright AI green color
        """

    elif line == "sys.print_int":
        compiled_assembly += """
        pop rax                 ; Fetch number from stack
        sub rsp, 32             ; SAFETY: Reserve stack buffer frame FIRST
        mov rcx, rsp            ; Position buffer pointer to bottom
        add rcx, 32             ; Move pointer to end to execute backward conversion
        mov rbx, 10             ; Base 10 hardware division
        
    .convert_loop_os:
        xor rdx, rdx            ; Clear RDX before division to prevent CPU faults
        idiv rbx                ; Divide RAX by 10. Remainder maps to RDX
        add dl, 0x30            ; Convert remainder integer into ASCII digit character
        dec rcx                 ; Shift buffer pointer one byte back
        mov [rcx], dl           ; Native, clean NASM instruction
        test rax, rax           ; Is calculation fully converted?
        jnz .convert_loop_os    ; If quotient remains, repeat execution loop
        
        mov rdi, 0xB8000        ; VGA text buffer base memory address
        mov rdx, rsp
        add rdx, 32             ; RDX marks top boundary of stack buffer
        
    .vga_print_loop:
        cmp rcx, rdx            ; Check if all digits have reached boundary
        je .vga_print_done
        mov al, [rcx]           ; Read ASCII byte from stack array
        mov [rdi], al           ; Output directly to hardware graphics terminal
        mov byte [rdi+1], 0x0A  ; Force bright AI green color schema
        add rdi, 2              ; Advance VGA character matrix grid pointer
        inc rcx                 ; Move to next sequential buffer digit
        jmp .vga_print_loop
        
    .vga_print_done:
        add rsp, 32             ; SAFETY: Completely restore local stack frame
        """
            
    else:
        print(f"Syntax Error on line {line_num}: Unknown command '{line}'")
        exit()

# ==============================================================================
# END OF PARSER LOOP (No indentation below this section!)
# ==============================================================================

# --- SECURE HARDWARE EXIT LOOP & BOOT SIGNATURE ---
compiled_assembly += """
    mov rsp, rbp                ; Restore local stack pointer framework
    pop rbp                     ; Restore base register anchor
.kernel_halt:
    hlt                         ; Safely put the CPU to sleep to save power
    jmp .kernel_halt            ; Lock the processor in a secure infinite wait loop

; --- MINIMALIST 64-BIT GLOBAL DESCRIPTOR TABLE (GDT) ---
align 8
gdt_start:
    dq 0x0000000000000000   ; Null Descriptor
gdt_code:
    dq 0x00209A0000000000   ; 64-bit Code Descriptor (Execute/Read, Ring 0)
gdt_data:
    dq 0x0000920000000000   ; 64-bit Data Descriptor (Read/Write, Ring 0)
gdt_end:

gdt_ptr:
    dw gdt_end - gdt_start - 1
    dq gdt_start

times 510-($-$$) db 0       ; Pad the rest of the 512-byte sector with zeros
dw 0xAA55                   ; The magic x86 boot signature (0xAA55)
"""




# --- APPEND DATA SECTION VIA NATIVE NASM SYNTAX ---
if strings_data:
    compiled_assembly += "\nsection .data\n"
    for idx, text in strings_data:
        # NASM beautifully handles pure string definitions via the 'db' directive!
        compiled_assembly += f'msg_{idx}: db "{text}", 0\n'

# --- 2. EXPORT RAW ASSEMBLER TEXT FILE ---
output_asm_file = "kernel.asm"
with open(output_asm_file, "w", encoding="utf-8") as f:
    f.write(compiled_assembly)

print("=========================================================")
print(f"-> STEP 1 SUCCESSFUL: Generated clean text '{output_asm_file}'")
print("=========================================================")
