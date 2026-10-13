BITS 16
org 0x7C00                  ; MBR entry address

start_bootloader:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00          ; Set up secure stack below bootloader

    ; ==========================================================================
    ; PHASE 11 (STEG A): INITIALIZE VESA BIOS EXTENSIONS (VBE) GRAFIKLÄGE
    ; ==========================================================================
    mov ax, 0x4F02          ; VBE-funktion: Sätt grafikläge
    mov bx, 0x4117          ; Läges-ID: 1024x768 @ 32-bit färg med Linear Framebuffer (0x117 + 0x4000)
    int 0x10                ; Anropa BIOS videotjänst
    cmp ax, 0x004F          ; Svarade grafikkortet med "Success" (0x004F)?
    jne .disk_error         ; Om inte, hoppa till felmeddelande och stanna

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
    mov dword [0xB008], 0xFD000083 ; Map the VESA Framebuffer area safely into 64-bit space

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
    BITS 64                         ; Berätta för NASM att vi kliver in i 64-bitars Long Mode!
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

        mov rdi, 0xB8000
        mov rcx, 2000
        mov ax, 0x0720
    .vga_clear_loop_1:
        mov [rdi], ax
        add rdi, 2
        loop .vga_clear_loop_1
        mov rdi, 0xB8000
        
    .flush_loop:
        in al, 0x64
        test al, 0x01
        jz .flush_done
        in al, 0x60
        jmp .flush_loop
    .flush_done:

    ; ==========================================================================
    ; PHASE 11 (STEG C): THE COMPLETE INTERACTIVE GRAPHICAL TERMINAL
    ; ==========================================================================
        mov rdi, 0x200000
    add rdi, 410000             ; Startposition (X=100, Y=100)

.terminal_input_loop:
    in al, 0x64                 ; Läs statusporten för PS/2
    test al, 0x01
    jz .terminal_input_loop
    
    in al, 0x60                 ; Hämta rå scankod [INDEX]

    ; --- KOLLA SPECIAL-TANGENTER ---
    cmp al, 0x1C                ; Enter
    je .handle_enter
    cmp al, 0x0E                ; Backspace
    je .handle_backspace
    cmp al, 0x39                ; Space
    je .handle_space

    ; --- TABELL-INDEXERING: Hitta rätt bokstavsadress ---
    ; Vi mappar scankoderna direkt till våra etiketter i font_rom
    mov rsi, font_rom           ; RSI pekar på början av vår font-rom
    
    cmp al, 0x17                ; Tryckte användaren på 'I'?
    je .load_I
    cmp al, 0x31                ; Tryckte användaren på 'N'?
    je .load_N
    cmp al, 0x2E                ; Tryckte användaren på 'C'?
    je .load_C
    cmp al, 0x1E                ; Tryckte användaren på 'A'?
    je .load_A
    
    jmp .terminal_input_loop    ; Okänd tangent? Strunt i den och vänta.

.load_I:
    add rsi, 0
    jmp .start_draw
.load_N:
    add rsi, 16
    jmp .start_draw
.load_C:
    add rsi, 32
    jmp .start_draw
.load_A:
    add rsi, 48
    jmp .start_draw


.start_draw:
    push rdi                    ; Spara nuvarande markörposition
    mov ecx, 16                 ; Alla våra bokstäver är nu exakt 16 rader höga!

.interactive_row_loop:
    push rcx
    mov bl, [rsi]               ; HÄMTA EN RÅ BYTE DIREKT FRÅN FONT-ROM I RAM!
    mov ecx, 8                  ; 8 pixlar per rad

.interactive_pixel_loop:
    shl bl, 1
    jnc .interactive_skip_pixel
    mov dword [rdi], 0x00FFFF00 ; Rita cyan-färgade pixlar [INDEX]
.interactive_skip_pixel:
    add rdi, 4
    loop .interactive_pixel_loop
    
    add rdi, (1024 * 4) - 32    ; Hoppa ner till nästa skärmrad
    inc rsi                     ; Stega framåt till nästa byte i vår font-rom!
    pop rcx
    loop .interactive_row_loop
    
    pop rdi
    add rdi, 48                 ; Flytta markören till nästa teckenruta
    jmp .clear_buffer_wait


; --- HARDWARE HANDLERS FÖR SPECIAL-TANGENTER ---

.handle_enter:
    ; 1. Hoppa ner exakt 16 pixlar vertikalt (16 rader * 1024 pixlar * 4 bytes = 65536 bytes)
    add rdi, 65536

    ; 2. SÄKERT VÄNSTER-CHASSI: Vi räknar ut exakt var den nya raden startar i minnet,
    ; och tvingar markören till en perfekt vänstermarginal (X = 100 pixlar in på skärmen).
    ; Vi tar den nuvarande adressen, drar av resten från radbredden, och lägger till marginalen (100 * 4 = 400 bytes)
    sub rdi, 0x200000           ; Dra av basadressen tillfälligt för ren rad-matte
    mov rax, rdi
    xor rdx, rdx
    mov rcx, 4096               ; En hel skärmrad är 4096 bytes (1024 * 4)
    div rcx                     ; RAX = Nuvarande radnummer, RDX = Hur långt till höger vi var
    sub rdi, rdx                ; Dra av nuvarande X-position så vi står exakt vid radens absoluta start!
    add rdi, 0x200000           ; Lägg tillbaka vår säkrade virtuella basadress
    
    add rdi, 400                ; Lägg till vår snygga och spikraka vänstermarginal (X=100)!
    jmp .clear_buffer_wait

.handle_space:
    add rdi, 48                 ; Ett mellanslag flyttar bara markören 12 pixlar åt höger utan att rita!
    jmp .clear_buffer_wait

.handle_backspace:
    sub rdi, 48                 ; Flytta markören 12 pixlar TILLBAKA åt vänster
    
    ; SUDDA UT DET GAMLA TECKNET: Vi ritar en tom svart box (0x00000000) över det gamla tecknet
    push rdi
    mov ecx, 16                 ; 16 rader hög radering
.erase_row_loop:
    push rcx
    mov ecx, 12                 ; 12 pixlar bred radering
.erase_pixel_loop:
    mov dword [rdi], 0x00000000 ; Skriv rent kolsvart minne (Radera!)
    add rdi, 4
    loop .erase_pixel_loop
    add rdi, (1024 * 4) - 48    ; Hoppa ner till nästa rad
    pop rcx
    loop .erase_row_loop
    pop rdi
    jmp .clear_buffer_wait

.clear_buffer_wait:
    in al, 0x64
    test al, 0x01
    jz .terminal_input_loop
    in al, 0x60
    jmp .clear_buffer_wait
        
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
font_rom:
    ; Varje block är exakt 16 bytes. 1 = tänd pixel, 0 = släckt.
    
    ; --- BOKSTAVEN 'I' (ASCII 73) ---
    .char_I:
        db 0x7E, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18
        db 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x7E

    ; --- BOKSTAVEN 'N' (ASCII 78) ---
    .char_N:
        db 0x66, 0x66, 0x66, 0x6E, 0x6E, 0x76, 0x76, 0x7A
        db 0x7A, 0x6E, 0x6E, 0x66, 0x66, 0x66, 0x66, 0x66

    ; --- BOKSTAVEN 'C' (ASCII 67) ---
    .char_C:
        db 0x3C, 0x66, 0x66, 0x40, 0x40, 0x40, 0x40, 0x40
        db 0x40, 0x40, 0x40, 0x40, 0x66, 0x66, 0x3C, 0x00

    ; --- BOKSTAVEN 'A' (ASCII 65) - Vår gamla trotjänare ---
    .char_A:
        db 0x18, 0x3C, 0x66, 0x66, 0x7E, 0x66, 0x66, 0x66
        db 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x00

section .pad
times 32768-($-$$) db 0
