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

    ; --- STEP 1B: FORCE PS/2 SET-1 TRANSLATION IN THE I8042 ---
    ; The key map below expects Set-1 make/break codes (e.g. 6=0x07,
    ; left bracket=0x1A, right bracket=0x1B). QEMU may otherwise expose
    ; Set-2 codes, causing punctuation to appear as unrelated symbols.
.wait_cmd_read:
    in al, 0x64
    test al, 0x02
    jnz .wait_cmd_read
    mov al, 0x20                ; Read controller command byte
    out 0x64, al
.wait_cmd_byte:
    in al, 0x64
    test al, 0x01
    jz .wait_cmd_byte
    in al, 0x60
    or al, 0x40                 ; Enable Set-2-to-Set-1 translation (bit 6)
    mov bl, al                  ; Preserve updated controller command byte
.wait_cmd_write:
    in al, 0x64
    test al, 0x02
    jnz .wait_cmd_write
    mov al, 0x60                ; Write controller command byte
    out 0x64, al
.wait_cmd_value:
    in al, 0x64
    test al, 0x02
    jnz .wait_cmd_value
    mov al, bl
    out 0x60, al

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
    jz .terminal_input_loop     ; Loop and wait safely

    in al, 0x60                 ; Fetch raw hardware scancode from keyboard

    ; =====================================================================
    ; TEMPORARY SCANCODE DEBUG MODE
    ; Display every raw byte from port 0x60 as two hexadecimal digits.
    ; This intentionally bypasses all existing key mapping/Shift logic.
    ; Example: key press 1E, key release 9E; Left Shift press 2A/release AA.
    ; =====================================================================
    movzx r12d, al
    mov eax, r12d
    shr eax, 4
    and eax, 0x0F
    lea rbx, [rel .debug_hex_digits]
    mov al, [rbx + rax]
    call .debug_draw_char

    mov eax, r12d
    and eax, 0x0F
    lea rbx, [rel .debug_hex_digits]
    mov al, [rbx + rax]
    call .debug_draw_char

    mov al, ' '
    call .debug_draw_char
    jmp .terminal_input_loop

.debug_hex_digits:
    db '0123456789ABCDEF'

; Draw ASCII character in AL at current RDI and advance cursor 12 pixels.
; Separate copy of the renderer keeps the normal keyboard path untouched.
.debug_draw_char:
    cmp al, 32
    jb .debug_draw_return
    cmp al, 126
    ja .debug_draw_return
    sub al, 32
    movzx rbx, al
    shl rbx, 4
    lea rsi, [rel font_rom]
    add rsi, rbx
    mov r10, rdi
    mov r11, rdi
    mov r8d, 16
.debug_row_loop:
    mov bl, [rsi]
    mov r9d, 8
.debug_pixel_loop:
    shl bl, 1
    jnc .debug_skip_pixel
    mov dword [rdi], 0xFF00FFFF
.debug_skip_pixel:
    add rdi, 4
    dec r9d
    jnz .debug_pixel_loop
    add r11, 4096
    mov rdi, r11
    inc rsi
    dec r8d
    jnz .debug_row_loop
    mov rdi, r10
    add rdi, 48
.debug_draw_return:
    ret

    ; --- PHASE 12: STATEFUL KEYBOARD TRACKING (SHIFT & CAPS HANDLING) ---
    cmp al, 0x2A                ; Left Shift Pressed
    je .shift_pressed_state
    cmp al, 0x36                ; Right Shift Pressed
    je .shift_pressed_state
    cmp al, 0xAA                ; Left Shift Released (Fångas NU upp innan bit 7-filtret!)
    je .shift_released_state
    cmp al, 0xB6                ; Right Shift Released (Fångas NU upp innan bit 7-filtret!)
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
    movzx r12d, al              ; Preserve raw Set-1 scancode before AL changes

    ; --- FINAL US QWERTY OVERRIDES: resolve these keys before any legacy logic ---
    ; Set-1 0x07 = physical 6 key; Shift+6 must always produce '^'.
    cmp r12d, 0x07
    jne .check_us_minus_key
    cmp byte [0x500], 1
    jne .continue_after_us_key_overrides
    mov al, '^'
    jmp .font_alignment_check_local

.check_us_minus_key:
    ; Set-1 0x0C = physical '-' key (immediately right of 0); Shift produces '_'.
    cmp r12d, 0x0C
    jne .check_us_grave_key_early
    cmp byte [0x500], 1
    jne .continue_after_us_key_overrides
    mov al, '_'
    jmp .font_alignment_check_local

.check_us_grave_key_early:
    ; Set-1 0x29 = key immediately left of 1: '`' / '~'.
    cmp r12d, 0x29
    jne .continue_after_us_key_overrides
    cmp byte [0x500], 1
    je .emit_us_grave_tilde_early
    mov al, 96
    jmp .font_alignment_check_local
.emit_us_grave_tilde_early:
    mov al, '~'
    jmp .font_alignment_check_local

.continue_after_us_key_overrides:
    ; --- TARGETED HARDWARE OVERRIDE: BUTTON LEFT OF Z ---
    cmp r12d, 0x56              ; Native ISO scancode for extra ISO key left of Z
    je .force_backslash_logic
    jmp .skip_z_override        ; If it's any other key, bypass this fix

.force_backslash_logic:
    cmp byte [0x500], 1         ; Is Shift held down?
    je .force_true_pipe         ; If Shift IS down, jump to our new pipe-injector!
    mov al, 92                  ; If Shift is NOT held down -> Force standard ASCII '\' (Backslash)
    jmp .caps_lock_check_local  ; Jump straight past translation to draw the backslash!

.force_true_pipe:
    mov al, 126                 ; Force ASCII 124, which is the true '|' (Pipe!)
    jmp .caps_lock_check_local  ; Jump straight past translation to draw the pipe!


.skip_z_override:

    ; US key immediately left of 1: ` without Shift, ~ with Shift.
    cmp r12d, 0x29
    jne .skip_grave_key
    cmp byte [0x500], 1
    je .emit_us_tilde
    mov al, 96                  ; ASCII backtick (`)
    jmp .font_alignment_check_local
.emit_us_tilde:
    mov al, 126                 ; ASCII tilde (~)
    jmp .font_alignment_check_local
.skip_grave_key:

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
    je .handle_enter
    cmp al, 0x0E                ; Backspace key scancode
    je .handle_backspace
    cmp al, 0x39                ; Spacebar key scancode
    je .handle_space

    ; --- HIGH-SPEED DIRECT INDEX TRANSLATION ---
    lea rbx, [rel scan_to_ascii] 
    

.read_normal_char_local:
    movzx rax, al               ; Read raw key index cleanly from AL
    mov al, [rbx + rax] 
    cmp al, 0
    je .terminal_input_loop     ; FIXED: Now points to your true local start loop!



    ; =========================================================================
    ; --- THE COMPLETE PURE AMERICAN HARDWARE OVERRIDE MATRIX ---
    ; =========================================================================

    ; 1. BUTTON LEFT OF Z: Force '\' (Normal) or '|' (Shift)
    cmp r12d, 0x56
    je .apply_backslash_logic
    ; Do not treat 0x1B as backslash: on US QWERTY it is the ] / } key.
    jmp .check_comma_key

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



.caps_lock_check_local:
    ; --- CAPS LOCK & SHIFT ALPHABET CONVERSION ENGINE ---
    cmp byte [0x501], 1         ; Is Caps Lock active?
    je .force_uppercase         ; If active, force uppercase!
    cmp byte [0x500], 1         ; Is Shift active instead?
    jne .font_alignment_check_local

.force_uppercase:
    ; --- HIGH-PRIORITY DIRECT HARDWARE OVERRIDE FOR SYMBOLS ---
    cmp r12d, 0x1A               ; Is it the raw scancode for the button right of P?
    je .force_open_brace_final
    cmp r12d, 0x1B               ; Is it the raw scancode for the next button to the right?
    je .force_close_brace_final
    jmp .not_grave_key




.not_grave_key:

    


    ; Check raw hardware scancodes for the number row (1 to 0, - and =)
    cmp r12d, 0x02               ; Button '1'
    je .force_excl
    cmp r12d, 0x03               ; Button '2'
    je .force_at
    cmp r12d, 0x04               ; Button '3'
    je .force_hash
    cmp r12d, 0x05               ; Button '4'
    je .force_dollar
    cmp r12d, 0x06               ; Button '5'
    je .force_percent
    cmp r12d, 0x07               ; Button '6'
    je .force_caret
    cmp r12d, 0x08               ; Button '7'
    je .force_amp
    cmp r12d, 0x09               ; Button '8'
    je .force_asterisk
    cmp r12d, 0x0A               ; Button '9'
    je .force_open_paren
    cmp r12d, 0x0B               ; Button '0'
    je .force_close_paren
    cmp r12d, 0x0C               ; Button '-'
    je .force_underscore
    cmp r12d, 0x0D               ; Button '='
    je .force_plus

    ; Check raw hardware scancodes for brackets right of P
    cmp r12d, 0x1A               ; Button right of P
    je .force_open_brace
    cmp r12d, 0x1B               ; Button right of that
    je .force_close_brace
    jmp .skip_all_shift_symbols

.force_excl:
    mov al, '!'
    jmp .font_alignment_check_local
.force_at:
    mov al, '@'
    jmp .font_alignment_check_local
.force_hash:
    mov al, '#'
    jmp .font_alignment_check_local
.force_dollar:
    mov al, '$'
    jmp .font_alignment_check_local
.force_percent:
    mov al, '%'
    jmp .font_alignment_check_local
.force_caret:
    mov al, '^'
    jmp .font_alignment_check_local
.force_amp:
    mov al, '&'
    jmp .font_alignment_check_local
.force_asterisk:
    mov al, '*'
    jmp .font_alignment_check_local
.force_open_paren:
    mov al, '('
    jmp .font_alignment_check_local
.force_close_paren:
    mov al, ')'
    jmp .font_alignment_check_local
.force_underscore:
    mov al, '_'
    jmp .font_alignment_check_local
.force_plus:
    mov al, '+'
    jmp .font_alignment_check_local
.force_open_brace:
    mov al, '{'
    jmp .font_alignment_check_local
.force_close_brace:
    mov al, '}'
    jmp .font_alignment_check_local


.skip_all_shift_symbols:
    jmp .process_alphabet_filtering



    jmp .process_alphabet_filtering


.force_open_brace_final:
    mov al, '{'                 ; Force true open curly brace directly!
    jmp .font_alignment_check_local

.force_close_brace_final:
    mov al, '}'                 ; Force true closing curly brace directly!
    jmp .font_alignment_check_local

.force_tilde_final:
    mov al, '~'                 ; Force true tilde symbol directly!
    jmp .font_alignment_check_local

.process_alphabet_filtering:
    ; --- STANDARD ALPHABET CONVERSION ---
    cmp al, 'a'
    jl .font_alignment_check_local
    cmp al, 'z'
    jg .font_alignment_check_local
    sub al, 32                  ; Convert cleanly to uppercase if Caps or Shift is active


    
.font_alignment_check_local:
    ; --- LINEAR FONT LOOKUP VIA UNIVERSAL ASCII INDEX ---
    sub al, 32                  ; Every printable ASCII glyph uses index ASCII-32




.apply_font_lookup:
    movzx rbx, al
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
