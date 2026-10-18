; === Copyright (C) 2026 Daniel Halen ===
; === This program is free software: you can redistribute it and/or modify ===
; === it under the terms of the GNU General Public License as published by ===
; === the Free Software Foundation, either version 3 of the License, or ===
; === (at your option) any later version. ===

default rel                     ; FIXED: Prevents implicit DEFAULT ABS deprecation warnings
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
; STAGE 2 KERNEL: Executed in pure 64-bit Long Mode (Freed from the 512-byte limit!)
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
    mov rdi, 0xFD000000         ; Start at the verified working QEMU LFB base address
    add rdi, 413696             ; Move down exactly 101 full rows vertically (101 * 4096)
    add rdi, 80                ; Apply clean left margin padding (X=100 pixels * 4 bytes)

    ; --- STEP 2B: INITIALIZE COMMAND BUFFER TRACKER ---
    mov dword [0x550], 0        ; Set command buffer length to 0 at boot (Stored at 0x550)

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
    jz .terminal_input_loop     ; Loop and wait safely

    in al, 0x60                 ; Fetch raw hardware scancode from keyboard
    


    ; --- PHASE 12: STATEFUL KEYBOARD TRACKING (SHIFT & CAPS HANDLING) ---
    cmp al, 0x2A                ; Left Shift Pressed
    je .shift_pressed_state
    cmp al, 0x36                ; Right Shift Pressed
    je .shift_pressed_state
    cmp al, 0xAA                ; Left Shift Released (handle before filtering key releases)
    je .shift_released_state
    cmp al, 0xB6                ; Right Shift Released (handle before filtering key releases)
    je .shift_released_state
    cmp al, 0x3A                ; Caps Lock Pressed
    je .caps_pressed_state

    ; Now we can safely skip normal key releases without blocking Shift!
    test al, 0x80
    jnz .terminal_input_loop
    
    jmp .process_ascii_lookup


.shift_pressed_state:
    mov byte [0x500], 1         ; Set Shift flag to ACTIVE (1) in safe RAM (0x500)
    jmp .terminal_input_loop

.shift_released_state:
    mov byte [0x500], 0         ; Set Shift flag to INACTIVE (0) in safe RAM (0x500)
    jmp .terminal_input_loop
    
.caps_pressed_state:
    xor byte [0x501], 1         ; Toggle Caps Lock flag (0 <-> 1) in safe RAM (0x501)
    jmp .terminal_input_loop

.process_ascii_lookup:
    ; --- TARGETED HARDWARE OVERRIDE: BUTTON LEFT OF Z ---
    cmp al, 0x56                ; Native ISO scancode for button left of Z
    je .force_backslash_logic
   
    jne .skip_z_override        ; If it's any other key, bypass this fix

.force_backslash_logic:
    cmp byte [0x500], 1         ; Is Shift held down?
    je .force_true_pipe         ; If Shift IS down, jump to our new pipe-injector!
    mov al, 92                  ; If Shift is NOT held down -> Force standard ASCII '\' (Backslash)
    jmp .caps_lock_check_local  ; Jump straight past translation to draw the backslash!

.force_true_pipe:
    mov al, 124                 ; ASCII 124 is the pipe character (|)
    jmp .caps_lock_check_local  ; Jump straight past translation to draw the pipe!


.skip_z_override:

    ; --- TARGETED HARDWARE OVERRIDE: BUTTON RIGHT OF L ---
    ; Physical button right of L sends hardware scancode 0x27
    cmp al, 0x27
    jne .skip_colon_override    ; If it's any other key, bypass this fix

    cmp byte [0x500], 1         ; Is Shift held down?
    jne .skip_colon_override    ; If Shift is NOT held down, bypass and keep your working normal ';' !
    
    mov al, 58                  ; If Shift IS held down -> Force standard ASCII ':' (Colon symbol)
    jmp .caps_lock_check_local  ; Jump straight past translation to draw the symbol!

.skip_colon_override:

    ; --- TARGETED HARDWARE OVERRIDE: BUTTON RIGHT OF COLON ---
    ; Physical button right of colon sends hardware scancode 0x28
    cmp al, 0x28
    jne .skip_quote_override    ; If it's any other key, bypass this fix

    cmp byte [0x500], 1         ; Is Shift held down?
    jne .skip_quote_override    ; If Shift is NOT held down, bypass and keep your working normal ''' !
    
    mov al, 34                  ; If Shift IS held down -> Force standard ASCII '"' (Double quote symbol)
    jmp .caps_lock_check_local  ; Jump straight past translation to draw the symbol!

.skip_quote_override:

    


    ; --- TARGETED HARDWARE OVERRIDE: BUTTON RIGHT OF COMMA ---
    ; Physical button right of comma sends hardware scancode 0x34
    cmp al, 0x34
    jne .skip_dot_override      ; If it's any other key, bypass this fix

    cmp byte [0x500], 1         ; Is Shift held down?
    jne .skip_dot_override      ; If Shift is NOT held down, bypass and keep your working normal '.' !
    
    mov al, 62                  ; If Shift IS held down -> Force standard ASCII '>' (Greater-Than symbol)
    jmp .caps_lock_check_local  ; Jump straight past translation to draw the symbol!



.skip_dot_override:

    ; --- TARGETED HARDWARE OVERRIDE: BUTTON RIGHT OF DOT ---
    ; Physical button right of dot sends hardware scancode 0x35
    cmp al, 0x35
    jne .skip_question_override ; If it's any other key, bypass this fix

    cmp byte [0x500], 1         ; Is Shift held down?
    jne .skip_question_override ; If Shift is NOT held down, bypass and keep your working normal '/' !
    
    mov al, 63                  ; If Shift IS held down -> Force standard ASCII '?' (Question mark)
    jmp .caps_lock_check_local  ; Jump straight past translation to draw the symbol!

.skip_question_override:


    ; --- TARGETED HARDWARE OVERRIDE: BUTTON NEXT TO ENTER ---
    ; Physical button next to Enter sends hardware scancode 0x2B
    cmp al, 0x2B
    jne .skip_enter_side_override ; If it's any other key, bypass this fix

    cmp byte [0x500], 1         ; Is Shift held down?
    jne .skip_enter_side_override ; If Shift is NOT held down, bypass and keep your working normal '\' !
    
    mov al, 126                 ; If Shift IS held down -> Force standard ASCII '|' (Pipe symbol aligned to font)
    jmp .caps_lock_check_local  ; Jump straight past translation to draw the symbol!

.skip_enter_side_override:

    

.skip_open_brace_override:



    ; --- TARGETED HARDWARE OVERRIDE: BUTTON RIGHT OF M ---
    ; Physical button right of M sends hardware scancode 0x33
    cmp al, 0x33
    jne .skip_m_override        ; If it's any other key, bypass this fix

    cmp byte [0x500], 1         ; Is Shift held down?
    jne .skip_m_override        ; If Shift is NOT held down, bypass and keep your working normal ',' !
    
    mov al, 60                  ; If Shift IS held down -> Force standard ASCII '<' (Less-Than symbol)
    jmp .caps_lock_check_local  ; Jump straight past translation to draw the symbol!

.skip_m_override:


    ; --- EVALUATE SPECIAL TERMINAL ACTIONS ---
    cmp al, 0x1C                ; Enter key scancode
    je .handle_enter            ; FIXED: Points directly to your local command engine!
    cmp al, 0x0E                ; Backspace key scancode
    je .handle_backspace
    cmp al, 0x39                ; Spacebar key scancode
    je .handle_space

    ; --- HIGH-SPEED DIRECT INDEX TRANSLATION ---
    lea rbx, [rel scan_to_ascii] 
    

.read_normal_char_local:
    movzx rax, al               ; Zero-extend the hardware scancode
    mov r12d, eax               ; Preserve the original scancode for symbol mapping
    mov al, [rbx + rax] 
    cmp al, 0
    je .terminal_input_loop     ; FIXED: Now points to your true local start loop!

    ; --- HIGH-SPEED RAM BUFFER LOGGER (TRUE ASCII POSITION) ---
    push rsi
    mov esi, 0x550              ; Load absolute RAM tracking address
    mov r14d, [rsi]             ; Read current buffer length
    cmp r14d, 63                ; Prevent buffer overflow (Max 64 characters)
    jge .skip_ram_logging_done
    
    movzx r15, r14d             ; Zero-extend length index to full 64-bit width
    mov esi, 0x600              ; Load absolute buffer base address
    mov [rsi + r15], al         ; SAVE TRUE ASCII CHARACTER TO RAM BUFFER!
    
    inc r14d                    ; Increment the character counter by exactly 1
    mov esi, 0x550
    mov [rsi], r14d             ; Save the updated length back to RAM

.skip_ram_logging_done:
    pop rsi                     ; Restore ESI cleanly



    ; =========================================================================
    ; --- THE COMPLETE PURE AMERICAN HARDWARE OVERRIDE MATRIX ---
    ; =========================================================================

    ; 1. BUTTON LEFT OF Z: Force '\' (Normal) or '|' (Shift)
    cmp r12d, 0x56
    je .apply_backslash_logic
    cmp r12d, 0x1B               ; Catch emulated layout swap for this specific key
    jne .check_comma_key

.apply_backslash_logic:
    cmp byte [0x500], 1         ; Is Shift held down?
    je .force_pure_pipe
    mov al, 92                  ; Force standard ASCII '\' (Backslash)
    jmp .caps_lock_check_local
.force_pure_pipe:
    mov al, 124                 ; ASCII 124 is the pipe character (|)
    jmp .caps_lock_check_local

.check_comma_key:
    ; 2. BUTTON RIGHT OF M: Force '<' when Shift is active
    cmp r12d, 0x33
    jne .check_dot_key
    cmp byte [0x500], 1         ; Is Shift held down?
    jne .caps_lock_check_local  ; If NOT down, bypass and keep working normal ','
    mov al, 60                  ; Force standard ASCII '<'
    jmp .caps_lock_check_local

.check_dot_key:
    ; 3. BUTTON RIGHT OF COMMA: Force '>' when Shift is active
    cmp r12d, 0x34
    jne .check_slash_key
    cmp byte [0x500], 1         ; Is Shift held down?
    jne .caps_lock_check_local  ; If NOT down, bypass and keep working normal '.'
    mov al, 62                  ; Force standard ASCII '>'
    jmp .caps_lock_check_local

.check_slash_key:
    ; 4. BUTTON RIGHT OF DOT: Force '?' when Shift is active
    cmp r12d, 0x35
    jne .check_colon_key
    cmp byte [0x500], 1         ; Is Shift held down?
    jne .caps_lock_check_local  ; If NOT down, bypass and keep working normal '/'
    mov al, 63                  ; Force standard ASCII '?'
    jmp .caps_lock_check_local

.check_colon_key:
    ; 5. BUTTON RIGHT OF L: Force ':' when Shift is active
    cmp r12d, 0x27
    jne .check_quote_key
    cmp byte [0x500], 1         ; Is Shift held down?
    jne .caps_lock_check_local  ; If NOT down, bypass and keep working normal ';'
    mov al, 58                  ; Force standard ASCII ':'
    jmp .caps_lock_check_local


.check_quote_key:
    ; 6. BUTTON RIGHT OF COLON: Force '"' when Shift is active
    cmp r12d, 0x28
    jne .caps_lock_check_local
    cmp byte [0x500], 1         ; Is Shift held down?
    jne .caps_lock_check_local  ; If NOT down, bypass and keep working normal '\''
    mov al, 34                  ; Force standard ASCII '"'
    jmp .caps_lock_check_local

; =========================================================================
; TODO: RETURN HERE LATER TO FINALIZE ADJUSTMENTS FOR ~ ^ _ { } Symbols and brackets [ ]
; Note: Current mapping is stable for typing letters, numbers, and Symbols !@#$%&*()+.
; =========================================================================

.caps_lock_check_local:
    ; Apply the US keyboard layout using the original hardware scancode.
    ; Shift changes punctuation; Caps Lock affects letters only.
    cmp byte [0x500], 1         ; Is either Shift key held?
    jne .check_caps_only

    ; Shifted number row: ! @ # $ % ^ & * ( ) _ +
    cmp r12d, 0x02
    je .sym_exclamation
    cmp r12d, 0x03
    je .sym_at
    cmp r12d, 0x04
    je .sym_hash
    cmp r12d, 0x05
    je .sym_dollar
    cmp r12d, 0x06
    je .sym_percent
    cmp r12d, 0x07
    je .sym_caret
    cmp r12d, 0x08
    je .sym_ampersand
    cmp r12d, 0x09
    je .sym_asterisk
    cmp r12d, 0x0A
    je .sym_left_paren
    cmp r12d, 0x0B
    je .sym_right_paren
    cmp r12d, 0x0C
    je .sym_underscore
    cmp r12d, 0x0D
    je .sym_plus

    ; Shifted punctuation around P and the home row
    cmp r12d, 0x29
    je .sym_tilde
    cmp r12d, 0x1A
    je .sym_left_brace
    cmp r12d, 0x1B
    je .sym_right_brace
    cmp r12d, 0x27
    je .sym_colon
    cmp r12d, 0x28
    je .sym_double_quote
    cmp r12d, 0x2B
    je .sym_pipe
    cmp r12d, 0x33
    je .sym_less_than
    cmp r12d, 0x34
    je .sym_greater_than
    cmp r12d, 0x35
    je .sym_question

    ; Shift uppercases letters, but leaves other characters unchanged.
    cmp al, 'a'
    jb .font_alignment_check_local
    cmp al, 'z'
    ja .font_alignment_check_local
    sub al, 32
    jmp .font_alignment_check_local

.check_caps_only:
    ; Caps Lock uppercases letters without changing punctuation.
    cmp byte [0x501], 1
    jne .font_alignment_check_local
    cmp al, 'a'
    jb .font_alignment_check_local
    cmp al, 'z'
    ja .font_alignment_check_local
    sub al, 32
    jmp .font_alignment_check_local

.sym_exclamation:
    mov al, '!'
    jmp .font_alignment_check_local
.sym_at:
    mov al, '@'
    jmp .font_alignment_check_local
.sym_hash:
    mov al, '#'
    jmp .font_alignment_check_local
.sym_dollar:
    mov al, '$'
    jmp .font_alignment_check_local
.sym_percent:
    mov al, '%'
    jmp .font_alignment_check_local
.sym_caret:
    mov al, '^'
    jmp .font_alignment_check_local
.sym_ampersand:
    mov al, '&'
    jmp .font_alignment_check_local
.sym_asterisk:
    mov al, '*'
    jmp .font_alignment_check_local
.sym_left_paren:
    mov al, '('
    jmp .font_alignment_check_local
.sym_right_paren:
    mov al, ')'
    jmp .font_alignment_check_local
.sym_underscore:
    mov al, '_'
    jmp .font_alignment_check_local
.sym_plus:
    mov al, '+'
    jmp .font_alignment_check_local
.sym_tilde:
    mov al, '~'
    jmp .font_alignment_check_local
.sym_left_brace:
    mov al, '{'
    jmp .font_alignment_check_local
.sym_right_brace:
    mov al, '}'
    jmp .font_alignment_check_local
.sym_colon:
    mov al, ':'
    jmp .font_alignment_check_local
.sym_double_quote:
    mov al, '"'
    jmp .font_alignment_check_local
.sym_pipe:
    mov al, '|'
    jmp .font_alignment_check_local
.sym_less_than:
    mov al, '<'
    jmp .font_alignment_check_local
.sym_greater_than:
    mov al, '>'
    jmp .font_alignment_check_local
.sym_question:
    mov al, '?'
    jmp .font_alignment_check_local
.font_alignment_check_local:
    ; --- LINEAR FONT LOOKUP VIA UNIVERSAL ASCII INDEX ---
    cmp al, 97
    jl .apply_standard_sub_local
    sub al, 1                   ; Correct off-by-one font shift for lowercase glyphs

.apply_standard_sub_local:
    sub al, 32                  ; AL now holds clean universal font index




.apply_font_lookup:
    movzx rbx, al
    shl rbx, 4                  ; Multiply by 16 bytes per font character matrix
    mov rsi, font_rom           ; Load absolute 64-bit base address of Font ROM into RSI
    add rsi, rbx                ; RSI now points exactly to target character matrix

    ; --- AUTOMATIC LINE BREAK INTERCEPTOR WITH BOTTOM CLEAR ---
    push rax
    push rcx
    push rdx
    push r14

    mov r14, 0xFD000000         ; QEMU LFB Base Address
    mov rax, rdi
    sub rax, r14                ; Get raw byte offset from start of screen
    
    ; Check if we have bled past the absolute bottom of the screen (Pixel 700 vertically)
    ; 700 rows * 4096 bytes per row = 2,867,200 bytes
    cmp rax, 2867200
    jb .check_right_margin      ; No -> Safe from bottom, go check right margin
    
    ; YES -> We reached the bottom! Clear screen or wrap around to top!
    mov rdi, 0xFD000000         ; Reset cursor to absolute top of screen
    add rdi, 410000             ; Snap back to starting position offset (X=100, Y=100)
    jmp .safe_no_line_break     ; Done! Bypass line break and draw safely

.check_right_margin:
    xor rdx, rdx
    mov rcx, 4096               ; Stride width of one full row
    div rcx                     ; rdx now holds current X coordinate in bytes
    
    cmp rdx, (500 * 4)          ; Passed pixel 900 horizontally?
    jb .safe_no_line_break
    
    ; Force newline
    mov [a32 0x560], rdi        ; FIXED: Save the exact true end-position of this row in RAM!
    add rdi, 65536              ; Move down 16 pixels
    sub rdi, rdx                ; Snap to left margin
    add rdi, 80                 ; X=20 padding


.safe_no_line_break:
    pop r14
    pop rdx
    pop rcx
    pop rax



    


.start_draw:


    mov r8, rdi                 ; FIXED: Copy core cursor to R8! R8 will do all the dirty row jumping.
    mov rcx, 16                 ; RCX = Outer loop counter (16 pixel rows high)

.interactive_row_loop:
    mov bl, [rsi]               ; Fetch 8-bit row pixel bitmap from Font ROM
    push r8                     ; Save the start of this specific pixel row on stack
    mov r9d, 8                  ; R9D = Inner loop counter (8 horizontal pixels per row)

.interactive_pixel_loop:
    shl bl, 1                   ; Shift highest bit into Carry Flag
    jnc .interactive_skip_pixel ; If bit is 0, leave background transparent
    
    ; Bit is 1! Render an intense light-blue pixel (Opaque Alpha + Cyan color)
    mov dword [r8], 0xFF00FFFF 

.interactive_skip_pixel:
    add r8, 4                   ; Move drawing pen 4 bytes right to next pixel
    dec r9d                     ; Decrement inner pixel counter
    jnz .interactive_pixel_loop ; Keep drawing horizontal pixels until R9D reaches 0

    ; --- CRITICAL PIXEL ROW REALIGNMENT ---
    pop r8                      ; Restore the start of the row we just drew
    add r8, 4096                ; Move drawing pen exactly 1 row down vertically (1024 * 4)
    
    inc rsi                     ; Move to the next font row byte in Font ROM
    loop .interactive_row_loop  ; Use optimized x86 LOOP instruction tied to RCX!
    
    ; --- ADVANCE THE GENUINE CURSOR TO NEXT CHARACTER BOX & LOG TO RAM ---
    ; 1. Save the ASCII character into our RAM buffer at 0x600
    push rsi                    ; Preserve RSI on the stack
    mov esi, 0x550              ; Load absolute RAM tracking address into ESI
    mov r14d, [rsi]             ; Read current buffer length
    cmp r14d, 63                ; Prevent buffer overflow (Max 64 characters)
    jge .skip_ram_log           ; If buffer is full, bypass logging
    
    ; Save the character byte (stored in AL) into the buffer at address (0x600 + index)
    movzx r15, r14d             ; Zero-extend length index to full 64-bit width
    mov esi, 0x600              ; Load absolute buffer base address into ESI
    mov [rsi + r15], al         ; Save character cleanly to RAM buffer!
    
    inc r14d                    ; Increment the character counter
    mov esi, 0x550              ; Point back to length address
    mov [rsi], r14d             ; Save the updated length back to RAM

.skip_ram_log:
    pop rsi                     ; Restore original RSI from stack
    add rdi, 48                 ; Advance cursor 12 pixels right to next char slot (12 * 4)
    jmp .terminal_input_loop    ; Return safely to keyboard listener loop





; ==============================================================================
; --- HARDWARE HANDLERS FOR SPECIAL TERMINAL KEYS ---
; ==============================================================================




.handle_enter:
    ; 1. Move cursor down exactly 16 pixels vertically for the next row
    add rdi, 65536

    ; --- VARIABLY ISOLATED SAFETY CHECK ---
    ; Check if the user typed anything on the current line before checking memory
    mov rax, 0x550
    mov r14d, [rax]             ; Read current row character counter
    cmp r14d, 0                 ; Is the row completely empty?
    je .no_command_typed        ; YES -> Jump straight to normal newline and DO NOT read ghost characters!

    ; --- ABSOLUTE FIRST-BYTE COMMAND PARSER ---
    ; If the line was not empty, check the absolute first character at 0x600
    mov rsi, 0x600
    mov al, [rsi]               ; Load the true start byte from RAM

    ; Check for Clear Command ('c' or 'C')
    cmp al, 'c'
    je .trigger_screen_clear
    cmp al, 'C'
    je .trigger_screen_clear

    ; Check for Reboot Command ('r' or 'R')
    cmp al, 'r'
    je .trigger_hardware_reboot
    cmp al, 'R'
    je .trigger_hardware_reboot

.no_command_typed:
    ; Reset the RAM character counter back to 0 for the next new row
    mov rax, 0x550
    mov dword [rax], 0

    ; 2. HARDWARE ALIGNMENT: Calculate carriage return using the true graphics base
    mov rbx, 0xFD000000         ; Load the correct physical LFB base address into 64-bit register
    sub rdi, rbx                ; Subtract base address temporarily for raw math
    
    mov rax, rdi
    xor rdx, rdx
    mov rcx, 4096               ; One full screen row width is 4096 bytes
    div rcx                     ; RAX = Row number, RDX = Current X offset
    
    sub rdi, rdx                ; Subtract X offset to snap back to absolute left margin
    add rdi, rbx                ; Add the true hardware base address back
    
    add rdi, 80                 ; Apply your clean left margin padding (X=20 pixels)
    jmp .terminal_input_loop    ; Jump back to wait for next key

.trigger_hardware_reboot:
    mov al, 0xFE
    out 0x64, al                ; Send a direct reset pulse to the PS/2 controller
    hlt
    jmp .trigger_hardware_reboot

.trigger_screen_clear:
    ; Pure geometric and isolated full video memory blanket wipe (1024 * 768)
    mov r11, 0xFD000000         ; Start at true LFB base address
    mov rax, 786432             ; Total screen pixels to overwrite with black
.clear_pixel_loop_bulk:
    mov dword [r11], 0x00000000 ; Write pure black pixel directly to screen
    add r11, 4                  
    dec rax                     ; Decrement our safe counter
    jnz .clear_pixel_loop_bulk  ; Keep wiping until RAX hits 0
    
    ; Reset your text cursor (RDI) back to the absolute top start row position
    mov rdi, 0xFD000000         
    add rdi, 413696             ; Align with text row Y=101
    add rdi, 80                 ; Align with your early left margin X=20
    
    ; Force clear the row count to 0 so the new top line starts completely fresh
    xor rax, rax                ; Safely zero out RAX register
    mov rbx, 0x550              ; Point directly to the row tracker memory address
    mov [rbx], eax              ; Write a clean 0 to memory using safe registers
    jmp .terminal_input_loop    ; Jump straight back to look for the next key








.handle_space:
    add rdi, 48                 ; Move 12 pixels right
    jmp .terminal_input_loop

.handle_backspace:
    ; --- PURE GEOMETRIC MULTI-ROW BACKSPACE (CRASH-PROOF) ---
    push rax
    push rbx
    push rcx
    push rdx

    mov rax, rdi
    mov rbx, 0xFD000000         ; QEMU LFB Base Address
    sub rax, rbx                ; Get raw byte offset from start of screen
    
    xor rdx, rdx
    mov rcx, 4096               ; Stride width of one full row (4096 bytes)
    div rcx                     ; RDX = Current X offset in bytes from row start
    
    cmp rdx, 80                 ; Are we at the left margin (Pixel 20 = 80 bytes)?
    jbe .backspace_wrap_up      ; YES -> Wrap up to the previous row line naturally!

    ; NO -> Standard backspace on the current line
    pop rdx
    pop rcx
    pop rbx
    pop rax
    
    sub rdi, 48                 ; Move cursor 12 pixels left cleanly
    
    ; Sync the RAM buffer counter so the command engine stays aligned
    push rsi
    mov esi, 0x550
    mov r14d, [rsi]
    cmp r14d, 0
    je .skip_ram_decrement
    dec r14d
    mov [rsi], r14d
    mov r15d, r14d
    mov esi, 0x600
    mov byte [rsi + r15], 0     ; Wipe character from RAM
.skip_ram_decrement:
    pop rsi
    jmp .do_pixel_erase

.backspace_wrap_up:
    ; Check if we are at the absolute top row to prevent screen bleeding
    mov rax, rdi
    mov rbx, 0xFD000000
    sub rax, rbx
    cmp rax, 413776             ; Is it the absolute top-left start (413696 + 80)?
    jbe .backspace_cancel_top   ; YES -> Block it, we can't erase higher than the top!

    ; NO -> Wrap up to the end of the previous line seamlessly!
    sub rdi, 65536              ; Move cursor UP exactly 16 pixel rows vertically
    sub rdi, rdx                ; Force X back to absolute 0 edge
    add rdi, (500 * 4)          ; Snap directly to your right margin (500 * 4)
    sub rdi, 48                 ; Step back 12 pixels to point to the last character box
    
    ; Sync RAM buffer counter safely
    push rsi
    mov esi, 0x550
    mov r14d, [rsi]
    cmp r14d, 0
    je .skip_ram_wrap_dec
    dec r14d
    mov [rsi], r14d
.skip_ram_wrap_dec:
    pop rsi

    pop rdx
    pop rcx
    pop rbx
    pop rax
    jmp .do_pixel_erase

.backspace_cancel_top:
    pop rdx
    pop rcx
    pop rbx
    pop rax
    jmp .terminal_input_loop

.do_pixel_erase:
    push rdi
    mov ecx, 16                 ; 16 rows high
.erase_row_loop:
    push rcx
    mov ecx, 12                 ; 12 pixels wide
.erase_pixel_loop:
    mov dword [rdi], 0x00000000 ; Pure black
    add rdi, 4
    loop .erase_pixel_loop
    add rdi, (1024 * 4) - 48    ; Next line
    pop rcx
    loop .erase_row_loop
    pop rdi
    jmp .terminal_input_loop







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
    ; --- LAYER 1: DEFAULT INTENSE CHARACTERS (Offset +0 bytes) ---
    ; Row 1: Scancodes 0x00 - 0x0F (` 1 2 3 4 5 6 7 8 9 0 - =)
    db 0,  96, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=',  0,  0
    ; Row 2: Scancodes 0x10 - 0x1F (q w e r t y u i o p [ ] Enter)
    db 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']',  0,  0, 'a', 's'
    ; Row 3: Scancodes 0x20 - 0x2F (d f g h j k l ; ' ` \ )
    db 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', 39,  96,  0, 92, 'z', 'x', 'c', 'v'
    ; Row 4: Scancodes 0x30 - 0x3F (b n m , . / )
    db 'b', 'n', 'm', ',', '.', '/',  0,  0,  0, ' ',  0,  0,  0,  0,  0,  0

    ; --- LAYER 2: SHIFTED INTENSE CHARACTERS (Offset +64 bytes) ---
    ; FIXED: Changed offset step from +128 to +64 bytes to guarantee absolute matrix mapping!
    ; Row 1 (Shifted): Scancodes 0x00 - 0x0F (~ ! @ # \$ % ^ & * ( ) _ +)
    db 0,  '~', '!', '@', '#', '\$', '%', '^', '&', '*', '(', ')', '_', '+',  0,  0
    ; Row 2 (Shifted): Scancodes 0x10 - 0x1F (Q W E R T Y U I O P { })
    db 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}',  0,  0,  0,  0 ; Row 2 Shifted
    ; Row 3 (Shifted): Scancodes 0x20 - 0x2F (D F G H J K L : " ~ |)
    db 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '"',  '~',  0, 124, 'Z', 'X', 'C', 'V'
    ; Row 4 (Shifted): Scancodes 0x30 - 0x3F (B N M < > ?)
    db 'B', 'N', 'M', '<', '>', '?',  0,  0,  0, ' ',  0,  0,  0,  0,  0,  0
















align 16
font_rom:
    ; --- INDEX 0: SPACEBAR (ASCII 32) ---
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; --- INDEX 1-15: COMMON SPECIAL CHARACTERS (PUNCTUATION & SYMBOLS) ---
    db 0x18, 0x18, 0x18, 0x18, 0x18, 0x00, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; !
    db 0x66, 0x66, 0x66, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; "
    db 0x24, 0x24, 0x7E, 0x24, 0x7E, 0x24, 0x24, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; #
    db 0x1C, 0x3E, 0x60, 0x3C, 0x06, 0x7C, 0x38, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; $
    db 0x62, 0x66, 0x0C, 0x18, 0x30, 0x64, 0x46, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; % (FIXED PLACEHOLDER)
    db 0x3C, 0x66, 0x3C, 0x38, 0x6C, 0x66, 0x3F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; & (FIXED PLACEHOLDER)
    db 0x18, 0x18, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; '
    db 0x0C, 0x18, 0x30, 0x30, 0x30, 0x18, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; (
    db 0x30, 0x18, 0x0C, 0x0C, 0x0C, 0x18, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; )
    db 0x00, 0x24, 0x18, 0x7E, 0x18, 0x24, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; * (FIXED PLACEHOLDER)
    db 0x18, 0x18, 0x7E, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; +
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x30, 0x30, 0x60, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; ,
    db 0x00, 0x00, 0x00, 0x7E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; -
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x30, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; .
    db 0x06, 0x0C, 0x18, 0x30, 0x60, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; /

    ; --- INDEX 16-25: NUMBERS 0 TO 9 (ASCII 48-57) ---
    db 0x3C, 0x66, 0x6E, 0x7E, 0x76, 0x66, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; 0
    db 0x18, 0x38, 0x18, 0x18, 0x18, 0x18, 0x7E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; 1
    db 0x3C, 0x66, 0x06, 0x0C, 0x30, 0x60, 0x7E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; 2
    db 0x3C, 0x66, 0x06, 0x1C, 0x06, 0x66, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; 3
    db 0x0C, 0x1C, 0x2C, 0x4C, 0x7E, 0x0C, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; 4
    db 0x7E, 0x60, 0x60, 0x7C, 0x06, 0x66, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; 5
    db 0x3C, 0x66, 0x60, 0x7C, 0x66, 0x66, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; 6
    db 0x7E, 0x66, 0x06, 0x0C, 0x18, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; 7
    db 0x3C, 0x66, 0x66, 0x3C, 0x66, 0x66, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; 8
    db 0x3C, 0x66, 0x66, 0x3E, 0x06, 0x66, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; 9

    ; --- INDEX 26-32: COLON, SEMICOLON etc. ---
    db 0x00, 0x18, 0x18, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; :
    db 0x00, 0x18, 0x18, 0x00, 0x18, 0x18, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; ;
    db 0x0C, 0x18, 0x30, 0x60, 0x30, 0x18, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; <
    db 0x00, 0x00, 0x7E, 0x00, 0x7E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; =
    db 0x30, 0x18, 0x0C, 0x06, 0x0C, 0x18, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; >
    db 0x3C, 0x66, 0x06, 0x0C, 0x18, 0x00, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; ?
    db 0x3C, 0x42, 0x5A, 0x56, 0x4E, 0x40, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; @ (FIXED PLACEHOLDER)

    ; --- INDEX 33-58: UPPERCASE ALPHABET A TO Z (ASCII 65-90) ---
    db 0x18, 0x3C, 0x66, 0x66, 0x7E, 0x66, 0x66, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; A
    db 0x7C, 0x66, 0x66, 0x7C, 0x66, 0x66, 0x7C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; B
    db 0x3C, 0x66, 0x60, 0x60, 0x60, 0x66, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; C
    db 0x78, 0x6C, 0x66, 0x66, 0x66, 0x6C, 0x78, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; D
    db 0x7E, 0x60, 0x60, 0x7C, 0x60, 0x60, 0x7E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; E
    db 0x7E, 0x60, 0x60, 0x7C, 0x60, 0x60, 0x60, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; F
    db 0x3C, 0x66, 0x60, 0x6C, 0x66, 0x66, 0x3E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; G
    db 0x66, 0x66, 0x66, 0x7E, 0x66, 0x66, 0x66, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; H
    db 0x3E, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x3E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; I
    db 0x1F, 0x06, 0x06, 0x06, 0x06, 0x66, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; J
    db 0x66, 0x6C, 0x78, 0x70, 0x78, 0x6C, 0x66, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; K
    db 0x60, 0x60, 0x60, 0x60, 0x60, 0x60, 0x7E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; L
    db 0x63, 0x77, 0x7F, 0x6B, 0x63, 0x63, 0x63, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; M
    db 0x66, 0x76, 0x7E, 0x7E, 0x6E, 0x66, 0x66, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; N
    db 0x3C, 0x66, 0x66, 0x66, 0x66, 0x66, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; O
    db 0x7C, 0x66, 0x66, 0x7C, 0x60, 0x60, 0x60, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; P
    db 0x3C, 0x66, 0x66, 0x66, 0x6E, 0x3C, 0x0E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; Q
    db 0x7C, 0x66, 0x66, 0x7C, 0x6C, 0x66, 0x66, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; R
    db 0x3C, 0x66, 0x30, 0x18, 0x0C, 0x66, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; S
    db 0x7E, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; T
    db 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; U
    db 0x66, 0x66, 0x66, 0x66, 0x24, 0x24, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; V
    db 0x63, 0x63, 0x63, 0x6B, 0x7F, 0x77, 0x63, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; W
    db 0x66, 0x66, 0x3C, 0x18, 0x3C, 0x66, 0x66, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; X
    db 0x66, 0x66, 0x66, 0x3C, 0x18, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; Y
    db 0x7E, 0x0C, 0x18, 0x30, 0x60, 0x60, 0x7E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; Z

    ; --- INDEX 59-64: TRAILING SYMBOLS ([ \ ] ^ _ `) ---
    db 0x3C, 0x30, 0x30, 0x30, 0x30, 0x30, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; [
    db 0x30, 0x18, 0x0C, 0x06, 0x03, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; \
    db 0x3C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; ]
    db 0x3C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; FIXED: Force ] here too!
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; _
    db 0x30, 0x30, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; `

    ; --- INDEX 65-90: LOWERCASE ALPHABET a TO z (ASCII 97-122) ---
    db 0x00, 0x00, 0x3C, 0x06, 0x3E, 0x66, 0x3E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; a
    db 0x60, 0x60, 0x7C, 0x66, 0x66, 0x66, 0x7C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; b
    db 0x00, 0x00, 0x3E, 0x60, 0x60, 0x66, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; c
    db 0x06, 0x06, 0x3E, 0x66, 0x66, 0x66, 0x3E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; d
    db 0x00, 0x00, 0x3C, 0x66, 0x7E, 0x60, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; e
    db 0x1C, 0x30, 0x78, 0x30, 0x30, 0x30, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; f
    db 0x00, 0x00, 0x3E, 0x66, 0x66, 0x3E, 0x06, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; g
    db 0x60, 0x60, 0x7C, 0x66, 0x66, 0x66, 0x66, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; h
    db 0x18, 0x00, 0x38, 0x18, 0x18, 0x18, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; i
    db 0x06, 0x00, 0x0E, 0x06, 0x06, 0x06, 0x66, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; j
    db 0x60, 0x60, 0x66, 0x6C, 0x78, 0x6C, 0x66, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; k
    db 0x38, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; l
    db 0x00, 0x00, 0x6E, 0x7F, 0x6B, 0x63, 0x63, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; m
    db 0x00, 0x00, 0x7C, 0x66, 0x66, 0x66, 0x66, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; n
    db 0x00, 0x00, 0x3C, 0x66, 0x66, 0x66, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; o
    db 0x00, 0x00, 0x7C, 0x66, 0x66, 0x7C, 0x60, 0x60, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; p
    db 0x00, 0x00, 0x3E, 0x66, 0x66, 0x3E, 0x06, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; q
    db 0x00, 0x00, 0x5C, 0x62, 0x60, 0x60, 0x60, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; r
    db 0x00, 0x00, 0x3E, 0x60, 0x3C, 0x06, 0x7C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; s
    db 0x30, 0x30, 0x7C, 0x30, 0x30, 0x30, 0x1C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; t
    db 0x00, 0x00, 0x66, 0x66, 0x66, 0x66, 0x3E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; u
    db 0x00, 0x00, 0x66, 0x66, 0x66, 0x24, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; v
    db 0x00, 0x00, 0x63, 0x63, 0x6B, 0x7F, 0x36, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; w
    db 0x00, 0x00, 0x66, 0x3C, 0x18, 0x3C, 0x66, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; x
    db 0x00, 0x00, 0x66, 0x66, 0x66, 0x3E, 0x06, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; y
    db 0x00, 0x00, 0x7E, 0x0C, 0x18, 0x30, 0x7E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; z
    db 0x0C, 0x18, 0x18, 0x30, 0x18, 0x18, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; { (Index 91)
    db 0x30, 0x18, 0x18, 0x0C, 0x18, 0x18, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; } (Index 92)
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; Empty gap padding
    db 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; | (Index 94)
    db 0x3C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; ] (Index 61)
    db 0x30, 0x18, 0x18, 0x0C, 0x18, 0x18, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; } (Index 93)
    db 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x00 ; | (Index 94)
    db 0x0C, 0x18, 0x18, 0x30, 0x18, 0x18, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; { (Index 91)



section .pad
times 32768-($-$$) db 0
