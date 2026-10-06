; === Copyright (C) 2026  Daniel Halen ===
; === This program is free software: you can redistribute it and/or modify ===
; === it under the terms of the GNU General Public License as published by ===
; === the Free Software Foundation, either version 3 of the License, or ===
; === (at your option) any later version. ===

; === FRAQSHIFT 64-BIT INSTRUCTION ENGINE: OP_LOAD_MATRIX (0xD0) ===

cmp al, 0xD0                    ; Is the command FRAQSHIFT_OP_LOAD_MATRIX?
jnz NEXT_FRAQ_OP                ; If not, skip to next (compiler calculates offset)

; --- 2. FETCH 64-BIT ADDRESSES ---
mov rsi, rbx                    ; RSI = Source address (from RBX)
mov rdi, 0x0000001000000000     ; RDI = The exact 64 GB memory interface (64-bit imm)

; --- 3. SILICON DUMP (64-bit DMA-loop) ---
; RCX contains the number of 4KB blocks. Shift left by 9 to get 8-byte (64-bit) dwords.
; 4096 bytes per page / 8 bytes per dword = 512 (2^9), so shl rcx, 9 is correct.
shl rcx, 9                      

rep movsq                       ; Stream the matrix data directly through the silicon!

; --- 4. INDICATE AI-GREEN 'M' ON SCREEN ---
; Direct hardware register write for immediate visual confirmation
mov rdx, 0xB80D8                ; Load absolute VGA address into register
mov byte [rdx], 0x4D            ; Write ASCII 'M'
mov byte [rdx+1], 0x0A          ; Write bright AI-green (attribute byte)

NEXT_FRAQ_OP:
hlt                             ; Halt and wait for next silicon cycle
jmp NEXT_FRAQ_OP
