; === Copyright (C) 2026 Daniel Halen ===
; === This program is free software: you can redistribute it and/or modify ===
; === it under the terms of the GNU General Public License as published by ===
; === the Free Software Foundation, either version 3 of the License, or ===
; === (at your option) any later version. ===

; === FRAQSHIFT 64-BIT INSTRUCTION ENGINE: OP_LOAD_MATRIX (0xD0) ===

run_compiler_pipeline:
            BITS 64             ; Tell NASM to interpret the following pipeline as pure 64-bit Long Mode!
            
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
            
            ; --- PIPELINE STEP 1: TOKENIZER ('I' = 73) ---
            mov rbx, [rbp - 40]
            movzx rax, byte [rbx]
            cmp al, 73
            jne .if_false_1

            ; --- PIPELINE STEP 2: 'N' = 78 ---
            mov rbx, [rbp - 48]
            movzx rax, byte [rbx]
            cmp al, 78
            jne .if_false_2

            ; --- PIPELINE STEP 3: 'C' = 67 ---
            mov rbx, [rbp - 56]
            movzx rax, byte [rbx]
            cmp al, 67
            jne .if_false_3

            ; --- PIPELINE STEP 4: SPACE = 32 ---
            mov rbx, [rbp - 64]
            movzx rax, byte [rbx]
            cmp al, 32
            jne .if_false_4

            ; --- PIPELINE STEP 5: SYMBOL TABLE LOOKUP ('X' = 88) ---
            mov rbx, [rbp - 72]
            movzx rax, byte [rbx]
            cmp al, 88
            jne .if_false_5

            ; --- SUCCESS NODE: EMIT TEST CODE TO MEMORY ---
            ; ÄNDRA HÄR: I stället för utropstecknet (33) laddar vi talet 63
            ; vilket är ASCII för ett vackert frågtecken '?' som vårt slutgiltiga kiselbevis!
            mov rax, 63
            mov rbx, [rbp - 80]
            mov [rbx], al
            mov qword [rbp - 88], 1    ; Success flag
            jmp .if_done_5

.if_false_5:
            mov qword [rbp - 88], 99
.if_done_5:
.if_false_4:
.if_false_3:
.if_false_2:
.if_false_1:
            ret
