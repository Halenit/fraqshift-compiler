BITS 16
org 0x7C00                  ; MBR entry address

start_bootloader:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00          ; Set up secure stack below bootloader

    ; ==========================================================================
    ; PHASE 11: INITIALIZE VESA BIOS EXTENSIONS (VBE) GRAPHICS MODE
    ; ==========================================================================
    mov ax, 0x4F02          ; VBE Function: Set Graphics Mode
    mov bx, 0x4117          ; FIXED: Force true 1024x768 @ 32-bit color Linear Framebuffer!
    int 0x10                ; Call BIOS video service
    cmp ax, 0x004F          ; Check if VBE function succeeded
    jne .disk_error         ; If graphics initialization failed, halt boot




    ; --- Load Stage 2 Kernel from Hard Disk ---
    mov ah, 0x02            ; BIOS Read Sectors function
    mov al, 60              ; Load 60 sectors (7.5 KB of code space)
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
    
    ; ==========================================================================
    ; PHASE 11: INITIAL 64-BIT BASE PAGE TABLES (16-BIT COMPLIANT)
    ; ==========================================================================
    mov dword [0x9000], 0xA003     ; PML4 index 0 -> PDPT (0xA000)
    mov dword [0xA000], 0xB003     ; GB 0 (0MB to 1GB) -> PD table for low RAM (0xB000)
    mov dword [0xA018], 0xC003     ; GB 3 (3GB to 4GB) -> Dedicated PD table for Graphics (0xC000)
    mov dword [0xB000], 0x0083     ; Identity map 0MB to 2MB (Kernel execution space)
    mov dword [0xB008], 0x00200083 ; Identity map 2MB to 4MB (Kernel extra heap room)





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
    BITS 64                         ; Inform NASM we are now in pure 64-bit Long Mode

    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    ; --- PHASE 11: 64-BIT HIGH-SPEED HARDWARE BRIDGES ---
    ; Safely map the true physical hardware memory regions inside 64-bit mode
    mov rax, 0xE0000083            ; QEMU VESA Standard Address with present/writable/size flags
    mov [0xC800], rax              ; Map directly to the 3.5GB threshold inside PD 2
    
    mov rax, 0xFD000083            ; QEMU Cirrus Legacy Address with flags
    mov [0xCF40], rax              ; Map directly to the 3.9GB threshold inside PD 2

    ; --- FLUSH CPU CACHE (TLB INVALIDATION) ---
    ; Force the MMU to immediately register the new hardware memory paths
    mov rax, cr3
    mov cr3, rax





kernel_main:
    push rbp
    mov rbp, rsp
    
    ; --- STEP 1: HARDWARE FLUSH (Completely empty old BIOS keyboard data) ---
.flush_loop:
    in al, 0x64                 ; Read PS/2 controller status register
    test al, 0x01               ; Check if Output Buffer contains ghost bytes
    jz .flush_done              ; If buffer is empty (0), hardware flush is complete
    in al, 0x60                 ; Read and discard the ghost byte
    jmp .flush_loop             ; Keep looping until every single old byte is cleared
.flush_done:

    ; --- STEP 2: INITIALIZE GRAPHICS TERMINAL CURSOR POSITION ---
    mov rdi, 0x50000            ; Switch back to a completely safe memory footprint if needed, or leave at 0xFD000000
    mov rdi, 0xFD000000         ; Keep the verified working QEMU LFB base
    add rdi, 410000             ; Starting position offset (X=100, Y=100)

    ; --- STEP 3: HARDWARE VERIFICATION (Enable PS/2 Keyboard Port) ---
.verify_keyboard_interface:

    in al, 0x64                 ; Read PS/2 controller status register
    test al, 0x02               ; Check if the controller input buffer is full
    jnz .verify_keyboard_interface ; If busy, loop and wait until clear
    mov al, 0xAE                ; PS/2 Command: Enable Keyboard Interface Port
    out 0x64, al                ; Send command to controller port

.terminal_input_loop:
    in al, 0x64                 ; Read PS/2 controller status port
    test al, 0x01               ; Check if data is present in output buffer
    jz .terminal_input_loop     ; If no key was pressed, loop and wait
    
    in al, 0x60                 ; Fetch raw hardware scancode from keyboard

    ; --- KERNEL FILTER: Ignore key release events (Break Codes >= 0x80) ---
    test al, 0x80
    jnz .terminal_input_loop    ; If key was released, skip and wait for next press

    ; --- 1. EVALUATE SPECIAL TERMINAL KEYS ---
    cmp al, 0x1C                ; Enter key scancode
    je .handle_enter
    cmp al, 0x0E                ; Backspace key scancode
    je .handle_backspace
    cmp al, 0x39                ; Spacebar key scancode
    je .handle_space



   

    ; --- 3. BOUNDS CHECK FOR SCANKODE RANGE ---
    cmp al, 0x58                ; Max scancode for standard keyboard keys
    ja .terminal_input_loop     ; If scancode is higher, ignore it

    ; --- 4. HIGH-SPEED DIRECT INDEX TRANSLATION ---
    lea rbx, [rel scan_to_ascii] ; Load absolute address of our translation table
    movzx rax, al               ; Move scancode into RAX to use as index
    mov al, [rbx + rax]         ; Fetch the true ASCII byte (e.g., 'A', 'B', 'C')
    cmp al, 0                   ; Check if the key has a valid ASCII mapping
    je .terminal_input_loop     ; If the mapped value is 0 (unmapped), ignore it

    ; --- 5. LINEAR FONT LOOKUP VIA UNIVERSAL ASCII INDEX ---
    sub al, 32                  ; AL now holds clean universal ASCII index (Space = 0)
    movzx rbx, al
    
    ; HARDWARE ALIGNMENT: Check if the character is an uppercase letter (ASCII >= 65)
    ; Since we subtracted 32, letters now start at index 33 (65 - 32 = 33)
    cmp rbx, 33
    jl .apply_linear_offset     ; If it's a number or space, skip font realignment
    
    ; If it's a letter, adjust lookup pointer to match our letter-only Font ROM layout
    sub rbx, 33                 ; Snap letters back to index 0 inside the ROM matrix

.apply_linear_offset:
    shl rbx, 4                  ; Multiply by 16 bytes per font character matrix
    mov rsi, font_rom           ; Load absolute 64-bit base address of Font ROM into RSI
    add rsi, rbx                ; RSI now points exactly to target character matrix

.start_draw:


    mov r10, rdi                ; Save the absolute original character base position in R10
    mov r11, rdi                ; R11 will act as our running row-start tracker
    mov r8d, 16                 ; R8D = Outer loop counter (16 pixel rows high)

.interactive_row_loop:
    mov bl, [rsi]               ; Fetch 8-bit row pixel bitmap from Font ROM
    mov r9d, 8                  ; R9D = Inner loop counter (8 horizontal pixels per row)

.interactive_pixel_loop:
    shl bl, 1                   ; Shift highest bit into Carry Flag
    jnc .interactive_skip_pixel ; If bit is 0, leave background transparent
    
    ; Bit is 1! Render an intense light-blue pixel (Opaque Alpha + Cyan color)
    mov dword [rdi], 0xFF00FFFF 

.interactive_skip_pixel:
    add rdi, 4                  ; Move cursor 4 bytes right to next horizontal pixel
    dec r9d                     ; Decrement inner pixel counter
    jnz .interactive_pixel_loop ; Keep drawing horizontal pixels until R9D reaches 0

    ; --- CRITICAL PIXEL ROW REALIGNMENT ---
    ; Advance our tracking pointer down exactly 1 row, then snap cursor to its start
    mov rax, 4096               ; Safe 64-bit row stride width (1024 width * 4 bytes)
    add r11, rax                ; Move row-start tracker down by 4096 bytes
    mov rdi, r11                ; Snap cursor straight to the start of this next row
    
    inc rsi                     ; Move to the next font row byte in Font ROM
    dec r8d                     ; Decrement outer row counter
    jnz .interactive_row_loop   ; Keep looping vertically until all 16 rows are drawn
    
    ; --- ADVANCE TO NEXT CHARACTER BOX ---
    mov rdi, r10                ; Restore the absolute original character base position
    mov rax, 48                 ; Advance cursor 12 pixels right to next char slot (12 * 4)
    add rdi, rax                ; Safely increment RDI with full 64-bit width
    jmp .terminal_input_loop    ; Return safely to keyboard listener loop

; ==============================================================================
; --- HARDWARE HANDLERS FOR SPECIAL TERMINAL KEYS ---
; ==============================================================================

.handle_enter:
    ; 1. Move cursor down exactly 16 pixels vertically (16 * 1024 * 4 bytes = 65536)
    add rdi, 65536

    ; 2. HARDWARE ALIGNMENT: Calculate carriage return using the true graphics base
    mov rbx, 0xFD000000            ; FIXED: Load the correct physical LFB base address into 64-bit register
    sub rdi, rbx                    ; Subtract base address temporarily for raw math
    
    mov rax, rdi
    xor rdx, rdx
    mov rcx, 4096               ; One full screen row width is 4096 bytes
    div rcx                     ; RAX = Row number, RDX = Current X offset
    
    sub rdi, rdx                ; Subtract X offset to snap back to absolute left margin
    add rdi, rbx                ; Add the true hardware base address back
    
    add rdi, 400                ; Apply clean left margin padding (X=100)
    jmp .terminal_input_loop    ; Jump back to wait for next key


.handle_space:
    add rdi, 48                 ; A spacebar press moves the cursor 12 pixels right without drawing
    jmp .terminal_input_loop

.handle_backspace:
    sub rdi, 48                 ; Move cursor 12 pixels back to the left (12 * 4 bytes)
    
    ; ERASE GLYPH: Overwrite character block with raw black pixels (0x00000000)
    push rdi
    mov ecx, 16                 ; 16 rows high erasure
.erase_row_loop:
    push rcx
    mov ecx, 12                 ; 12 pixels wide erasure
.erase_pixel_loop:
    mov dword [rdi], 0x00000000 ; Write pure black pixel to screen
    add rdi, 4
    loop .erase_pixel_loop
    add rdi, (1024 * 4) - 48    ; Jump down to next screen row
    pop rcx
    loop .erase_row_loop
    pop rdi
    jmp .terminal_input_loop    ; Safely jump back to input loop

    ; --- CRITICAL KERNEL ISOLATION BARRIER ---
    ; This infinite jump prevents the CPU from bleeding down into the compiler code!
    jmp $                       ; Halt the processor inside the terminal interface forever

; ==============================================================================
; COMPILER ENGINE PIPELINE SECTION (LEAVE UNTOUCHED BELOW THIS LINE)
; ==============================================================================

        
            mov rax, 327680
            mov [rbp - 8], rax
            
            mov rbx, [rbp - 8]   ; Load memory address into RBX
                        mov rax, 73        ; Load immediate literal
            mov [rbx], al               ; Write data directly via register
            inc qword [rbp - 8]
            inc qword [rbp - 8]
            inc qword [rbp - 8]
            inc qword [rbp - 8]
            inc qword [rbp - 8]
            inc qword [rbp - 8]
            inc qword [rbp - 8]
            inc qword [rbp - 8]

            mov rbx, [rbp - 8]   ; Load memory address into RBX
                        mov rax, 78        ; Load immediate literal
            mov [rbx], al               ; Write data directly via register
            inc qword [rbp - 8]
            inc qword [rbp - 8]
            inc qword [rbp - 8]
            inc qword [rbp - 8]
            inc qword [rbp - 8]
            inc qword [rbp - 8]
            inc qword [rbp - 8]
            inc qword [rbp - 8]

            mov rbx, [rbp - 8]   ; Load memory address into RBX
                        mov rax, 67        ; Load immediate literal
            mov [rbx], al               ; Write data directly via register
            inc qword [rbp - 8]
            inc qword [rbp - 8]
            inc qword [rbp - 8]
            inc qword [rbp - 8]
            inc qword [rbp - 8]
            inc qword [rbp - 8]
            inc qword [rbp - 8]
            inc qword [rbp - 8]

            mov rbx, [rbp - 8]   ; Load memory address into RBX
                        mov rax, 32        ; Load immediate literal
            mov [rbx], al               ; Write data directly via register

            mov rax, 328000
            mov [rbp - 16], rax
            
            mov rbx, [rbp - 16]   ; Load memory address into RBX
                        mov rax, 88        ; Load immediate literal
            mov [rbx], al               ; Write data directly via register
            inc qword [rbp - 16]
            inc qword [rbp - 16]
            inc qword [rbp - 16]
            inc qword [rbp - 16]
            inc qword [rbp - 16]
            inc qword [rbp - 16]
            inc qword [rbp - 16]
            inc qword [rbp - 16]

            mov rbx, [rbp - 16]   ; Load memory address into RBX
                        mov rax, 8        ; Load immediate literal
            mov [rbx], al               ; Write data directly via register

            call run_compiler_pipeline            ; Jump to function entry node
            
            mov rax, 754304
            mov [rbp - 24], rax
            
            mov rax, 329000
            mov [rbp - 32], rax
            
            mov rbx, [rbp - 32]   ; Load memory address
            movzx rax, byte [rbx]       ; Fetch EXACTLY one 8-bit byte and zero upper bits!
            push rax                    ; Push clean value onto calculation stack
            
            mov rbx, [rbp - 24]   ; Load memory address into RBX
                        mov [rbx], al               ; Write data directly via register
            inc qword [rbp - 24]

            mov rbx, [rbp - 24]   ; Load memory address into RBX
                        mov rax, 10        ; Load immediate literal
            mov [rbx], al               ; Write data directly via register

    .wait_for_key:
        in al, 0x64
        test al, 0x01
        jz .wait_for_key
        in al, 0x60
        movzx rax, al
        push rax
        
    mov rsp, rbp
    pop rbp

.kernel_halt:
    hlt
    jmp .kernel_halt

run_compiler_pipeline:

            mov rax, 327680
            mov [rbp - 40], rax
            
            mov rax, 327688
            mov [rbp - 48], rax
            
            mov rax, 327696
            mov [rbp - 56], rax
            
            mov rax, 327704
            mov [rbp - 64], rax
            
            mov rax, 328000
            mov [rbp - 72], rax
            
            mov rax, 329000
            mov [rbp - 80], rax
            
            mov rbx, [rbp - 40]   ; Load memory address
            movzx rax, byte [rbx]       ; Fetch EXACTLY one 8-bit byte and zero upper bits!
            push rax                    ; Push clean value onto calculation stack
            
            pop rax
            cmp rax, 73
            jne .if_false_1

            mov rbx, [rbp - 48]   ; Load memory address
            movzx rax, byte [rbx]       ; Fetch EXACTLY one 8-bit byte and zero upper bits!
            push rax                    ; Push clean value onto calculation stack
            
            pop rax
            cmp rax, 78
            jne .if_false_2

            mov rbx, [rbp - 56]   ; Load memory address
            movzx rax, byte [rbx]       ; Fetch EXACTLY one 8-bit byte and zero upper bits!
            push rax                    ; Push clean value onto calculation stack
            
            pop rax
            cmp rax, 67
            jne .if_false_3

            mov rbx, [rbp - 64]   ; Load memory address
            movzx rax, byte [rbx]       ; Fetch EXACTLY one 8-bit byte and zero upper bits!
            push rax                    ; Push clean value onto calculation stack
            
            pop rax
            cmp rax, 32
            jne .if_false_4

            mov rbx, [rbp - 72]   ; Load memory address
            movzx rax, byte [rbx]       ; Fetch EXACTLY one 8-bit byte and zero upper bits!
            push rax                    ; Push clean value onto calculation stack
            
            pop rax
            cmp rax, 88
            jne .if_false_5

            mov rax, 33        ; Load value directly into hardware register
            
            mov rbx, [rbp - 80]   ; Load memory address into RBX
                        mov [rbx], al               ; Write data directly via register

            mov rbx, 1        ; Load value directly into hardware register
                        jmp .if_done_5
.if_false_5:

            mov rbx, 99        ; Load value directly into hardware register
            .if_done_5:
            jmp .if_done_4
.if_false_4:

            mov rbx, 99        ; Load value directly into hardware register
            .if_done_4:
            jmp .if_done_3
.if_false_3:

            mov rbx, 99        ; Load value directly into hardware register
            .if_done_3:
            jmp .if_done_2
.if_false_2:

            mov rbx, 99        ; Load value directly into hardware register
            .if_done_2:
            jmp .if_done_1
.if_false_1:

            mov rbx, 99        ; Load value directly into hardware register
            .if_done_1:

            ret


align 16
scan_to_ascii:
    ; Index matches the raw hardware scancode from port 0x60
    db 0,  0, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=',  0,  0 ; 0x00 - 0x0F
    db 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '[', ']',  0,  0, 'A', 'S' ; 0x10 - 0x1F
    db 'D', 'F', 'G', 'H', 'J', 'K', 'L', ';', 39,  '`',  0, 92, 'Z', 'X', 'C', 'V' ; 0x20 - 0x2F
    db 'B', 'N', 'M', ',', '.', '/',  0,  0,  0, ' ',  0,  0,  0,  0,  0,  0 ; 0x30 - 0x3F
    times 128 db 0                                                           ; Pad out the rest of the table


align 16
font_rom:
        ; --- LETTER A (Index 0) ---
    db 0x18, 0x3C, 0x66, 0x66, 0x7E, 0x66, 0x66, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; --- LETTER B (Index 1) ---
    db 0x7C, 0x66, 0x66, 0x7C, 0x66, 0x66, 0x7C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; --- LETTER C (Index 2) ---
    db 0x3C, 0x66, 0x60, 0x60, 0x60, 0x66, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; --- LETTER D (Index 3) ---
    db 0x78, 0x6C, 0x66, 0x66, 0x66, 0x6C, 0x78, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; --- LETTER E (Index 4) ---
    db 0x7E, 0x60, 0x60, 0x7C, 0x60, 0x60, 0x7E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; --- LETTER F (Index 5) ---
    db 0x7E, 0x60, 0x60, 0x7C, 0x60, 0x60, 0x60, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; --- LETTER G (Index 6) ---
    db 0x3C, 0x66, 0x60, 0x6C, 0x66, 0x66, 0x3E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; --- LETTER H (Index 7) ---
    db 0x66, 0x66, 0x66, 0x7E, 0x66, 0x66, 0x66, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; --- LETTER I (Index 8) ---
    db 0x3E, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x3E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; --- LETTER J (Index 9) ---
    db 0x1F, 0x06, 0x06, 0x06, 0x06, 0x66, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; --- LETTER K (Index 10) ---
    db 0x66, 0x6C, 0x78, 0x70, 0x78, 0x6C, 0x66, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; --- LETTER L (Index 11) ---
    db 0x60, 0x60, 0x60, 0x60, 0x60, 0x60, 0x7E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; --- LETTER M (Index 12) ---
    db 0x63, 0x77, 0x7F, 0x6B, 0x63, 0x63, 0x63, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; --- LETTER N (Index 13) ---
    db 0x66, 0x76, 0x7E, 0x7E, 0x6E, 0x66, 0x66, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; --- LETTER O (Index 14) ---
    db 0x3C, 0x66, 0x66, 0x66, 0x66, 0x66, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; --- LETTER P (Index 15) ---
    db 0x7C, 0x66, 0x66, 0x7C, 0x60, 0x60, 0x60, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; --- LETTER Q (Index 16) ---
    db 0x3C, 0x66, 0x66, 0x66, 0x6E, 0x3C, 0x0E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; --- LETTER R (Index 17) ---
    db 0x7C, 0x66, 0x66, 0x7C, 0x6C, 0x66, 0x66, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; --- LETTER S (Index 18) ---
    db 0x3C, 0x66, 0x30, 0x18, 0x0C, 0x66, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; --- LETTER T (Index 19) ---
    db 0x7E, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; --- LETTER U (Index 20) ---
    db 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; --- LETTER V (Index 21) ---
    db 0x66, 0x66, 0x66, 0x66, 0x24, 0x24, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; --- LETTER W (Index 22) ---
    db 0x63, 0x63, 0x63, 0x6B, 0x7F, 0x77, 0x63, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; --- LETTER X (Index 23) ---
    db 0x66, 0x66, 0x3C, 0x18, 0x3C, 0x66, 0x66, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; --- LETTER Y (Index 24) ---
    db 0x66, 0x66, 0x66, 0x3C, 0x18, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; --- LETTER Z (Index 25) ---
    db 0x7E, 0x0C, 0x18, 0x30, 0x60, 0x60, 0x7E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00


section .pad
times 32768-($-$$) db 0
