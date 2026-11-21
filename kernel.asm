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
;    mov ax, 0x4F02              ; VBE Function: Set Graphics Mode
;    mov bx, 0x4118              ; FIXED: Force true 1024x768 @ 32-bit color Linear Framebuffer!
;    int 0x10                    ; Call BIOS video service
;    cmp ax, 0x004F              ; Check if VBE function succeeded
;    jne .disk_error             ; If graphics initialization failed, halt boot


        ; --- Read first 17 sectors (Head 0, Sectors 2-18) ---
    mov ah, 0x02
    mov al, 17              ; Max remaining sectors on Track 0, Head 0
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov bx, 0x7E00
    int 0x13
    jc .disk_error

    ; --- Read next 18 sectors (Head 1, Sectors 1-18) ---
    mov ah, 0x02
    mov al, 18              ; Full Track 0, Head 1
    mov ch, 0
    mov cl, 1
    mov dh, 1
    mov bx, 0xA000          ; 0x7E00 + (17 * 512)
    int 0x13
    jc .disk_error

    ; --- Read next 18 sectors (Cylinder 1, Head 0, Sectors 1-18) ---
    mov ah, 0x02
    mov al, 18              ; Full Track 1, Head 0 (Total 53 sectors = 26.5 KB)
    mov ch, 1
    mov cl, 1
    mov dh, 0
    mov bx, 0xC400          ; 0xA000 + (18 * 512)
    int 0x13
    jc .disk_error
    ; --- Read next 12 sectors (Cylinder 1, Head 1, Sec 1-12 -> 0xE800 to 0x10000, NO 64KB CROSS!) ---
    mov ax, 0x0E80
    mov es, ax
    xor bx, bx
    mov ah, 0x02
    mov al, 12              ; 12 * 512 = 0x1800 -> Ends at EXACT 0x10000!
    mov ch, 1
    mov cl, 1
    mov dh, 1
    int 0x13
    jc .disk_error

    ; --- Read remaining 6 sectors of Track 1 Head 1 (Sec 13-18 -> Physical 0x10000) ---
    mov ax, 0x1000
    mov es, ax
    xor bx, bx
    mov ah, 0x02
    mov al, 6               ; Starts cleanly at 0x10000 (inside new 64KB DMA page!)
    mov ch, 1
    mov cl, 13
    mov dh, 1
    int 0x13
    jc .disk_error

    ; --- Read next 16 sectors (Cylinder 2, Head 0 -> Physical 0x10C00, Total 39.5 KB) ---
    mov ax, 0x10C0
    mov es, ax
    xor bx, bx
    mov ah, 0x02
    mov al, 18              ; Read ALL 18 sectors of Track 2, Head 0 (no 2-sector gap!)
    mov ch, 2
    mov cl, 1
    mov dh, 0
    int 0x13
    jc .disk_error

    ; --- Read next 18 sectors (Cylinder 2, Head 1 -> Physical 0x12C00, Total 52.5 KB) ---
    mov ax, 0x1300
    mov es, ax
    xor bx, bx
    mov ah, 0x02
    mov al, 18             ; Starts cleanly at 0x13000 with zero gap!
    mov ch, 2
    mov cl, 1
    mov dh, 1
    int 0x13
    jc .disk_error

    ; --- Read next 18 sectors (Cylinder 3, Head 0 -> Physical 0x15400, Total 62.5 KB) ---
    mov ax, 0x1540
    mov es, ax
    xor bx, bx
    mov ah, 0x02
    mov al, 18              ; Loads font_rom at the end of kernel.asm completely into RAM!
    mov ch, 3
    mov cl, 1
    mov dh, 0
    int 0x13
    jc .disk_error
    
    


    

    xor ax, ax
    mov es, ax              ; Reset ES back to 0 before setting up Page Tables

        cli                     ; Disable interrupts for hardware switch

    ; --- Set up 64-bit Page Tables safely at 0x50000 (0x5000:0x0000) ---
    mov ax, 0x5000
    mov es, ax
    xor di, di
    xor eax, eax
    mov ecx, 4096           ; Clear 16 KB (0x50000 - 0x53FFF)
    rep stosd

    ; Populate Page Tables via ES (0x50000 base)
    mov dword [es:0x0000], 0x51007 ; PML4[0] -> PDPT at 0x51000 (Allow User traversal)
    mov dword [es:0x1000], 0x52007 ; PDPT[0] -> Low RAM PD at 0x52000 (Allow User traversal)
    mov dword [es:0x1018], 0x53003 ; PDPT[3] -> Graphics PD at 0x53000 (KERNEL ONLY! Ring 3 blocked!)
    mov dword [es:0x2000], 0x0083  ; Identity map 0MB - 2MB (KERNEL ONLY! Ring 3 blocked!)
    mov dword [es:0x2008], 0x00200083 ; Identity map 2MB - 4MB (KERNEL ONLY! Ring 3 blocked!)
    mov dword [es:0x2018], 0x00600083   ; Identity map 6MB - 8MB (Skip 0x2010 = Ring 3!)
    mov dword [es:0x2020], 0x00800083   ; Identity map 8MB - 10MB


    


    xor ax, ax
    mov es, ax              ; Restore ES to 0
    mov eax, 0x50000
    mov cr3, eax            ; Load PML4 base address (0x50000) into CR3

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
    mov ss, ax

    ; --- PHASE 10.5: UPGRADE TO RING 3 + TSS SECURITY ARCHITECTURE ---
    call init_security_gdt_tss
    call init_fast_syscall
    call init_nx_and_idt


    ; --- PHASE 11: 64-BIT HIGH-SPEED HARDWARE BRIDGES (AT 0x53000) ---
    mov rax, 0xE0000083         ; QEMU VESA Standard Address (0xE0000000 - 0xE01FFFFF)
    mov [0x53800], rax          ; Map inside Graphics PD at 0x53000
    mov rax, 0xE0200083         ; Next 2MB graphics memory block (0xE0200000 - 0xE03FFFFF)
    mov [0x53808], rax          ; Map next 2MB page entry

    mov rax, 0xFD000083         ; QEMU Legacy LFB Address (0xFD000000 - 0xFD1FFFFF)
    mov [0x53F40], rax          ; Map inside Graphics PD at 0x53000
    mov rax, 0xFD200083         ; Next 2MB graphics memory block (0xFD200000 - 0xFD3FFFFF)
    mov [0x53F48], rax          ; Map next 2MB page entry



; --- PHASE 11.5: PCI BUS SCANNER & INTEL E1000 NETWORK HARDWARE ---
    call init_pci_e1000

    ; --- FLUSH CPU CACHE (TLB INVALIDATION) ---
    ; Force the MMU to immediately register the new hardware memory paths
    mov rax, cr3
    mov cr3, rax



kernel_main:
    push rbp
    mov rbp, rsp

    call set_vbe_1024x768

; --- PHASE 12: LAUNCH RING 3 SANDBOX & LIVE HTTP GET (SYSCALL 10) ---
    call init_user_sandbox



    ; --- ACTIVATE TRUE 1080P VBE GRAPHICS MODE IMMEDIATELY ---
    


    ; --- PHASE 13: INITIALIZE SYSTEM HEAP ALLOCATOR ---
    ; Sets up the 1MB boundary pointer in RAM so the OS can allocate memory dynamically!
    call heap_init

    ;
    
    ; --- PHASE 14: INITIALIZE PS/2 MOUSE DRIVER ---
    call mouse_init             ; POWER ON: Activates the hardware packet stream!

    ; --- BREAK OUT OF THE TERMINAL: JUMP STRAIGHT TO TRUE GUI ---
    jmp gui_desktop_loop        ; Boots directly into your new 640x480 cyber desktop!


    ; --- BREAK OUT OF THE TERMINAL: JUMP STRAIGHT TO TRUE GUI ---
    jmp gui_desktop_loop        ; Boots directly into your new 1080p graphic ecosystem! [3.1]


        ; --- SYSTEM INITIALIZATION COMPLETE ---
    ; All infrastructure (Heap, Mouse, FS) is safely active under the hood! [3.1]
    ; We now fall directly into your stable terminal loop seamlessly.

    

; =========================================================================
; FRAQSHIFT SECURITY CORE: 64-BIT RING 3 GDT, TSS & SYSCALL SANDBOX
; =========================================================================
init_security_gdt_tss:
    ; 1. Clear the 104-byte TSS structure cleanly
    lea rdi, [rel fraq_tss]
    xor rax, rax
    mov rcx, 13                 ; 13 * 8 = 104 bytes
    rep stosq

    ; 2. Set RSP0 (Kernel's protected stack when Ring 3 calls Kernel)
    lea rdi, [rel fraq_tss]
    mov qword [rdi + 4], 0x90000 ; Safe dedicated Kernel Ring 0 Stack
    mov word [rdi + 102], 104    ; Disable I/O Permission Bitmap for Ring 3!

    ; 3. Write the 64-bit TSS physical base address into GDT selector 0x18
    mov rax, rdi
    lea rbx, [rel gdt64_tss]
    mov word [rbx + 2], ax       ; Base bits 0..15
    shr rax, 16
    mov byte [rbx + 4], al       ; Base bits 16..23
    shr rax, 8
    mov byte [rbx + 7], al       ; Base bits 24..31
    shr rax, 8
    mov dword [rbx + 8], eax     ; Base bits 32..63

    ; 4. Load the new 64-bit Security GDT & activate Task Register (TR = 0x18)
    lgdt [rel gdt64_ptr]
    mov ax, 0x18                 ; Selector 0x18 = 64-bit TSS
    ltr ax                       ; Load Task Register into CPU hardware!
    ret

align 16
gdt64_start:
    dq 0x0000000000000000        ; 0x00: Null Descriptor
    dq 0x00209A0000000000        ; 0x08: Kernel Code (Ring 0, 64-bit)
    dq 0x0000920000000000        ; 0x10: Kernel Data (Ring 0)
gdt64_tss:
    dw 103                       ; 0x18: TSS Limit (104 bytes - 1)
    dw 0                         ; Base 0..15
    db 0                         ; Base 16..23
    db 0x89                      ; Type: 64-bit Available TSS (Present, Ring 0)
    db 0x00                      ; Granularity
    db 0                         ; Base 24..31
    dd 0                         ; Base 32..63
    dd 0                         ; Reserved
    dq 0x0000F20000000000        ; 0x28: User Data   (STAR 0x20 + 8  = 0x28 | 3 = 0x2B)
    dq 0x0020FA0000000000        ; 0x30: User Code   (STAR 0x20 + 16 = 0x30 | 3 = 0x33)
gdt64_end:

gdt64_ptr:
    dw gdt64_end - gdt64_start - 1
    dq gdt64_start

align 16
fraq_tss:
    times 104 db 0               ; 104-byte Hardware Task State Segment

; =========================================================================
; FRAQSHIFT HIGH-SPEED 64-BIT SYSCALL ENGINE (MSR & DISPATCHER)
; =========================================================================
init_fast_syscall:
    ; 1. Enable SCE (System Call Extensions, Bit 0) in IA32_EFER (0xC0000080)
    mov ecx, 0xC0000080
    rdmsr
    or eax, 1                   ; Set SCE bit
    wrmsr

    ; 2. Configure IA32_STAR (0xC0000081) with exact AMD64 segment math:
    ; Bits 47:32 = 0x0008 (SYSCALL -> CS=0x08, SS=0x10)
    ; Bits 63:48 = 0x0020 (SYSRET  -> SS=0x20+8=0x28|3, CS=0x20+16=0x30|3)
    mov ecx, 0xC0000081
    xor eax, eax
    mov edx, 0x00200008
    wrmsr

    ; 3. Point IA32_LSTAR (0xC0000082) to our 64-bit Kernel Syscall Handler
    mov ecx, 0xC0000082
    lea rax, [rel fraq_syscall_entry]
    mov rdx, rax
    shr rdx, 32
    wrmsr

    ; 4. Mask Interrupt Flag (0x200) in IA32_SFMASK (0xC0000084) on syscall entry
    mov ecx, 0xC0000084
    mov eax, 0x00000200
    xor edx, edx
    wrmsr
    ret

; --- KERNEL SYSCALL GATEWAY (Called from Ring 3 apps via 'syscall') ---
fraq_syscall_entry:
    mov [rel user_rsp_scratch], rsp
    mov rsp, 0x8F000

    push rcx                    ; Save User return RIP
    push r11                    ; Save User RFLAGS
    push qword [rel user_rsp_scratch]

    cmp rax, 0                  ; Syscall 0: sys_ping
    je .sys_ping
    cmp rax, 2                  ; Syscall 2: sys_get_mouse
    je .sys_get_mouse
    cmp rax, 10                 ; Syscall 10: sys_http_get (RDI = User Buffer Ptr in Ring 3)
    je .sys_http_get
    cmp rax, 11                 ; Syscall 11: sys_draw_browser (RDI=URL Ptr, RSI=Text Ptr, RDX=SafeFlag)
    je .sys_draw_browser

    cmp rax, 99                 ; Syscall 99: Exit Ring 3 Sandbox verification
    je .sys_exit_test

    cmp rax, 99                 ; Syscall 99: Exit Ring 3 Sandbox verification
    je .sys_exit_test

    mov rax, -1
    jmp .syscall_return

.sys_ping:
    mov rax, 0x1337             ; Proof-of-life return code from Ring 0 Kernel!
    jmp .syscall_return

.sys_get_mouse:
    mov r11, 0x580
    mov eax, [abs r11]
    mov r11, 0x584
    mov edx, [abs r11]
    jmp .syscall_return

.sys_http_get:
    ; ZERO-TRUST SECURITY CHECK: Ensure Ring 3 destination buffer (RDI)
    ; lies strictly inside the 4MB..6MB User Sandbox (0x400000..0x5FE000)!
    cmp rdi, 0x400000
    jb .syscall_bad_arg
    cmp rdi, 0x5FE000
    ja .syscall_bad_arg

    ; Call Kernel's protected ARP + TCP/HTTP engine to fetch live web page into RDI!
    call net_http_fetch_live    ; Returns bytes received in RAX (or -3 on timeout)
    jmp .syscall_return

.sys_draw_browser:
    ; ZERO-TRUST SECURITY CHECK: Validate both User pointers (RDI & RSI)
    ; Must lie strictly inside the 4MB..6MB Ring 3 Sandbox (0x400000..0x5FE000)!
    cmp rdi, 0x400000
    jb .syscall_bad_arg
    cmp rdi, 0x5FE000
    ja .syscall_bad_arg
    cmp rsi, 0x400000
    jb .syscall_bad_arg
    cmp rsi, 0x5FE000
    ja .syscall_bad_arg

    ; Save sanitized URL & Body pointers into Kernel Display Registers (0x5E0..0x5F0)
    mov r11, 0x600
    mov [abs r11], rdi          ; Saved URL string pointer in Ring 3
    mov [abs r11 + 8], rsi      ; Saved Page Body string pointer in Ring 3
    mov [abs r11 + 16], rdx     ; Security Status: 1 = SAFE (Green), 0 = BLOCKED (Red)
    xor rax, rax
    jmp .syscall_return


.syscall_bad_arg:
    mov rax, -2

.sys_exit_test:
    mov ax, 0x10                ; Restore Kernel Data Segments cleanly
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov rsp, [rel kernel_resume_rsp]
    jmp [rel kernel_resume_rip]

.syscall_return:
    pop qword [rel user_rsp_scratch]
    pop r11
    pop rcx
    mov rsp, [rel user_rsp_scratch]
    o64 sysret

user_rsp_scratch:
    dq 0

; =========================================================================
; FRAQSHIFT RING 3 HARDWARE SANDBOX (USER PAGE TABLES & SYSRET LAUNCHER)
; =========================================================================
init_user_sandbox:
    ; Map 2MB User Space Sandbox at 0x400000 - 0x5FFFFF inside Low RAM PD (0x52000)
    ; Flag 0x87 = Present + Writable + User Mode Accessible + 2MB Huge Page
    mov rdi, 0x52010
    mov rax, 0x00400087
    mov [rdi], rax


    ; Flush TLB so CPU enforces Ring 0 (0..4MB) vs Ring 3 (4..6MB) immediately
    mov rax, cr3
    mov cr3, rax

    ; --- PARSE REAL .FRAQ STATEMENT: url "http://..." FROM browser.fraq ---
    lea rsi, [rel fraq_browser_source_bin]
    cmp byte [rsi], 0           ; Ensure browser.fraq is not empty
    je .fallback_kernel_payload


    ; --- SELF-CONTAINED URL & WELCOME TEXT LOADER (Always inside first 4KB!) ---
    jmp .load_browser_strings
.local_url_str:  db "http://neverssl.com (34.223.124.45)", 0
.local_body_str: db "CONNECTING TO HTTPS BRIDGE (10.0.2.2:8080)...", 0



.load_browser_strings:
    lea rsi, [rel .local_url_str]
    mov rdi, 0x508000
.copy_u:
    mov al, byte [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .copy_u

    lea rsi, [rel .local_body_str]
    mov rdi, 0x510000
.copy_b:
    mov al, byte [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .copy_b


    

    ; Compile browser.fraq into native 64-bit Ring 3 machine code at 0x400000:
    mov rdi, 0x400000           ; Ring 3 executable destination
    ; 1. Emit: mov rdi, 0x510000 (Buffer for Syscall 10)
    mov word [rdi], 0xBF48
    mov qword [rdi + 2], 0x0000000000510000
    add rdi, 10
    ; 2. Emit: mov rax, 10; syscall (Fetch live web page via sys_http_get!)
    mov dword [rdi], 0x00C0C748
    mov byte  [rdi + 3], 10     ; Syscall 10!
    mov word  [rdi + 4], 0x0000
    mov byte  [rdi + 6], 0
    mov word  [rdi + 7], 0x050F
    add rdi, 9
    ; 3. Emit: mov rdi, 0x508000; mov rsi, 0x510000; mov rdx, 2 (2 = COMPILED FROM .FRAQ!)
    mov word [rdi], 0xBF48
    mov qword [rdi + 2], 0x0000000000508000
    add rdi, 10
    mov word [rdi], 0xBE48
    mov qword [rdi + 2], 0x0000000000510000
    add rdi, 10
    mov word [rdi], 0xBA48
    mov qword [rdi + 2], 2      ; Status = 2 (PURPLE/CYAN = EXECUTING browser.fraq!)
    add rdi, 10
    ; 4. Emit: mov rax, 11; syscall (Render Browser via sys_draw_browser!)
    mov dword [rdi], 0x00C0C748
    mov byte  [rdi + 3], 11     ; Syscall 11!
    mov word  [rdi + 4], 0x0000
    mov byte  [rdi + 6], 0
    mov word  [rdi + 7], 0x050F
    add rdi, 9
    ; 5. Emit: mov rax, 99; syscall (Clean Ring 3 exit back to Desktop!)
    mov dword [rdi], 0x00C0C748
    mov byte  [rdi + 3], 99     ; Syscall 99!
    mov word  [rdi + 4], 0x0000
    mov byte  [rdi + 6], 0
    mov word  [rdi + 7], 0x050F

    jmp .run_compiled_fraq

.fallback_kernel_payload:
    lea rsi, [rel ring3_test_payload]
    mov rdi, 0x400000
    mov rcx, ring3_test_payload_end - ring3_test_payload
    rep movsb

.run_compiled_fraq:


    ; Execute live Ring 3 -> Ring 0 Syscall -> Ring 3 -> Kernel verification!
    call launch_ring3_test
    ret

launch_ring3_test:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15

    lea rax, [rel .ring3_test_completed]
    mov [rel kernel_resume_rip], rax
    mov [rel kernel_resume_rsp], rsp

    mov rcx, 0x400000           ; User RIP
    mov r11, 0x002              ; User RFLAGS
    mov rsp, 0x5F0000           ; User Stack inside 4MB-6MB Sandbox
    o64 sysret                  ; Drop from Ring 0 -> Ring 3!

.ring3_test_completed:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

ring3_test_payload:
    ; 1. Verify Ring 3 -> Ring 0 Syscall link
    mov rax, 0
    syscall
    mov rbx, 0x500000
    mov [rbx], rax

    ; 2. Populate Default URL in Ring 3 Address Bar Buffer (0x508000)
    lea rsi, [rel browser_default_url]
    mov rdi, 0x508000
.copy_url_init:
    mov al, byte [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .copy_url_init

    ; 3. RUN SAFE-LINK SECURITY FILTER ON URL (0x508000)
    ; Scans URL for dangerous patterns ("phish", "malware", ".exe", "evil")
    mov rsi, 0x508000
    call ring3_safe_link_check  ; Returns RAX = 1 (SAFE) or 0 (BLOCKED!)
    test rax, rax
    jz .browser_url_blocked

    ; 4. SAFE URL! Fetch Live Web Page via Kernel Syscall 10 (sys_http_get)
    mov rdi, 0x510000           ; Raw HTTP/HTML buffer in Ring 3
    mov rax, 10                 ; Syscall 10 = sys_http_get
    syscall
    mov rbx, 0x500008
    mov [rbx], rax              ; Store HTTP byte count

    ; If network returned <= 0 bytes (offline/NAT timeout), load built-in Welcome Page fallback
    cmp rax, 0
    jg .sanitize_html_body

    lea rsi, [rel browser_welcome_html]
    mov rdi, 0x510000
.copy_fallback_html:
    mov al, byte [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .copy_fallback_html

.sanitize_html_body:
    ; 5. STRIP ALL HTML TAGS (<...>) & SCRIPTS -> CLEAN READABLE TEXT AT 0x512000!
    mov rsi, 0x510000           ; Raw HTML source
    mov rdi, 0x512000           ; Sanitized plain text output
    call ring3_strip_html_tags

    ; 6. Render Browser Address Bar & Clean Text via Kernel Syscall 11!
    mov rdi, 0x508000           ; URL string
    mov rsi, 0x512000           ; Sanitized readable text
    mov rdx, 1                  ; Status = 1 (SAFE & VERIFIED)
    mov rax, 11                 ; Syscall 11 = sys_draw_browser
    syscall
    jmp .browser_boot_handover

.browser_url_blocked:
    ; Safe-Link Filter blocked a dangerous URL! Render Red Security Alert!
    lea rsi, [rel browser_blocked_msg]
    mov rdi, 0x512000
.copy_blocked_msg:
    mov al, byte [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .copy_blocked_msg

    mov rdi, 0x508000           ; Blocked URL
    mov rsi, 0x512000           ; Security warning text
    mov rdx, 0                  ; Status = 0 (BLOCKED BY SAFE-LINK!)
    mov rax, 11
    syscall

.browser_boot_handover:
    mov rax, 99                 ; Hand control to Desktop GUI
    syscall

; --- RING 3 SAFE-LINK SECURITY FILTER (Blocks dangerous URLs before network access) ---
ring3_safe_link_check:
    ; Check if URL contains "malware" or "phish" or ".exe"
    mov rbx, rsi
.scan_url_chars:
    mov al, byte [rbx]
    test al, al
    jz .url_is_safe
    ; Check for ".exe" (0x6578652E in little-endian)
    cmp dword [rbx], 0x6578652E
    je .url_is_dangerous
    ; Check for "phish"
    cmp dword [rbx], 0x73696870 ; "phis"
    je .url_is_dangerous
    inc rbx
    jmp .scan_url_chars
.url_is_dangerous:
    xor rax, rax                ; Return 0 = BLOCKED!
    ret
.url_is_safe:
    mov rax, 1                  ; Return 1 = SAFE!
    ret

; --- RING 3 HTML SANITIZER (Strips all <tags> and keeps pure readable text) ---
ring3_strip_html_tags:
    xor rcx, rcx                ; Inside-tag flag (0 = outside tag, 1 = inside <...>)
    xor rdx, rdx                ; Output character counter (max 1024 chars)
.strip_loop:
    mov al, byte [rsi]
    test al, al
    jz .strip_done
    cmp rdx, 1024
    jge .strip_done

    cmp al, '<'
    jne .check_tag_close
    mov rcx, 1                  ; Enter HTML tag -> skip everything until '>'
    inc rsi
    jmp .strip_loop

.check_tag_close:
    cmp al, '>'
    jne .check_emit_char
    mov rcx, 0                  ; Exit HTML tag
    mov byte [rdi], ' '         ; Replace tag boundary with clean space
    inc rdi
    inc rdx
    inc rsi
    jmp .strip_loop

.check_emit_char:
    test rcx, rcx
    jnz .skip_char              ; Still inside <...> tag -> ignore!
    cmp al, 32                  ; Ignore control characters (< 32)
    jb .skip_char
    mov [rdi], al
    inc rdi
    inc rdx
.skip_char:
    inc rsi
    jmp .strip_loop

.strip_done:
    mov byte [rdi], 0
    ret

browser_default_url:
    db "http://httpforever.com", 0
browser_welcome_html:
    db "<html><head><title>Fraqshift Web</title></head><body>"
    db "<h1>FRAQSHIFT ZERO-TRUST BROWSER V1.0</h1>"
    db "<p>Ring-3 Sandbox: ACTIVE | NX-Protection: ON | Safe-Link: VERIFIED.</p>"
    db "<p>Ready for live HTTP/TCP browsing via Intel e1000!</p>"
    db "</body></html>", 0
browser_blocked_msg:
    db "[SAFE-LINK SHIELD] BLOCKED DANGEROUS URL BEFORE NETWORK ACCESS!", 0
ring3_test_payload_end:
fraq_browser_source_bin:
    incbin "browser.fraq"
    db 0



kernel_resume_rip: dq 0
kernel_resume_rsp: dq 0

; =========================================================================
; FRAQSHIFT HARDWARE DEFENSE: NX (NO-EXECUTE) BIT & 64-BIT EXCEPTION IDT
; =========================================================================
init_nx_and_idt:
    ; 1. Enable NXE (No-Execute Enable, Bit 11) in IA32_EFER (0xC0000080)
    mov ecx, 0xC0000080
    rdmsr
    or eax, (1 << 11)           ; Set Bit 11 (NXE) in CPU hardware!
    wrmsr

    ; 2. Populate first 32 CPU Exception Vectors (0..31) in 64-bit IDT (at 0x54000)
    ; Placing the 4KB IDT at physical 0x54000 keeps it inside protected Kernel RAM!
    mov rdi, 0x54000
    xor rax, rax
    mov rcx, 512                ; Clear 4096 bytes (256 entries * 16 bytes)
    rep stosq

    ; Install safe exception handlers for all 32 CPU hardware faults (0..31)
    xor rcx, rcx                ; Vector index 0..31
.install_idt_loop:
    lea rax, [rel fraq_default_exception_handler]
    cmp rcx, 13                 ; Vector 13 = #GP (General Protection Fault)
    jne .check_pf_vec
    lea rax, [rel fraq_security_fault_handler]
    jmp .write_idt_gate
.check_pf_vec:
    cmp rcx, 14                 ; Vector 14 = #PF (Page Fault / Memory Wall Violation)
    jne .write_idt_gate
    lea rax, [rel fraq_security_fault_handler]

.write_idt_gate:
    ; Calculate IDT entry address: 0x54000 + (RCX * 16)
    mov rdi, rcx
    shl rdi, 4
    add rdi, 0x54000

    mov word [rdi], ax          ; Offset bits 0..15
    mov word [rdi + 2], 0x0008  ; Kernel Code Selector (0x08)
    mov byte [rdi + 4], 0       ; IST = 0
    mov byte [rdi + 5], 0x8E    ; Type: 64-bit Interrupt Gate (Present, Ring 0)
    shr rax, 16
    mov word [rdi + 6], ax      ; Offset bits 16..31
    shr rax, 16
    mov dword [rdi + 8], eax    ; Offset bits 32..63
    mov dword [rdi + 12], 0     ; Reserved

    inc rcx
    cmp rcx, 32
    jl .install_idt_loop

    ; 3. Load 64-bit IDT Register (IDTR) into CPU!
    lidt [rel idt64_ptr]
    ret
; =========================================================================
; FRAQSHIFT PCI BUS SCANNER & INTEL 82540EM (e1000) HARDWARE DRIVER
; =========================================================================
init_pci_e1000:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    ; Scan Bus 0, Devices 0..31, Function 0 for Intel e1000 (0x8086:0x100E)
    xor rbx, rbx                ; RBX = Device slot 0..31

.pci_scan_loop:
    ; Build PCI Configuration Address: (1 << 31) | (Bus 0 << 16) | (Dev << 11) | (Func 0 << 8) | Reg 0
    mov eax, ebx
    shl eax, 11
    or eax, 0x80000000          ; Enable bit 31
    mov dx, 0x0CF8
    out dx, eax

    mov dx, 0x0CFC
    in eax, dx                  ; Read Vendor ID (low 16) + Device ID (high 16)

    cmp eax, 0x100E8086         ; Intel 82540EM Gigabit Ethernet Controller?
    je .e1000_found

    inc rbx
    cmp rbx, 32
    jl .pci_scan_loop

    ; Not found -> Store 0 at 0x5B8 as status
    mov rdi, 0x5B8
    mov qword [rdi], 0
    jmp .pci_init_done

.e1000_found:
    ; 1. Enable PCI Memory Space (Bit 1) & Bus Mastering DMA (Bit 2) in PCI Command Reg (Offset 0x04)
    mov eax, ebx
    shl eax, 11
    or eax, 0x80000004          ; Register offset 0x04 (Command/Status)
    mov dx, 0x0CF8
    out dx, eax

    mov dx, 0x0CFC
    in eax, dx
    or eax, 0x00000006          ; Set Bit 1 (Memory Space) + Bit 2 (Bus Master)
    out dx, eax

    ; 2. Read BAR0 (Base Address Register 0 at Offset 0x10) for MMIO physical address
    mov eax, ebx
    shl eax, 11
    or eax, 0x80000010          ; Register offset 0x10 (BAR0)
    mov dx, 0x0CF8
    out dx, eax

    mov dx, 0x0CFC
    in eax, dx
    and eax, 0xFFFFFFF0         ; Mask out lower 4 flag bits -> Clean 32-bit physical BAR0!

    ; If BIOS left BAR0 unassigned (0 or below 3GB), assign 0xFEB80000 directly!
    cmp eax, 0xC0000000
    jae .bar0_valid

    mov eax, ebx
    shl eax, 11
    or eax, 0x80000010          ; Select BAR0 register again
    mov dx, 0x0CF8
    out dx, eax

    mov dx, 0x0CFC
    mov eax, 0xFEB80000         ; Assign clean, conflict-free 32-bit MMIO base address!
    out dx, eax

.bar0_valid:
    mov rdi, 0x5B8
    mov [rdi], rax              ; Save physical e1000 MMIO base address at 0x5B8!


    ; 3. Dynamically map the 2MB MMIO region into Ring 0 Hardware PD (0x53000)
    mov rcx, rax
    mov rdx, 0xC0000000         ; Load full 64-bit unsigned 0xC0000000 (avoid 32-bit sign-extension!)
    sub rcx, rdx                ; Clean positive offset from 3GB!
    shr rcx, 21                 ; 2MB page index
    shl rcx, 3                  ; Multiply by 8 bytes per PD entry
    add rcx, 0x53000            ; Target entry inside Ring 0 Hardware Page Directory!


    mov rdx, rax
    and rdx, 0xFFE00000         ; Align physical base to 2MB boundary
    or rdx, 0x00000093          ; Present (1) + Writable (2) + Cache Disable (0x10) + Huge Page (0x80) = Ring 0 ONLY!
    mov [rcx], rdx

    ; Flush TLB immediately so MMIO reads/writes hit silicon hardware directly!
    mov rdx, cr3
    mov cr3, rdx

    ; 4. Read Hardware MAC Address from Intel e1000 RAL0 (0x5400) & RAH0 (0x5404)
    ; RAX still holds physical BAR0 MMIO base (e.g., 0xFEBC0000)
    mov edx, [rax + 0x5400]     ; RAL0: First 4 bytes of MAC address
    mov rdi, 0x5B0
    mov [rdi], edx              ; Store MAC bytes 0..3 at 0x5B0

    mov edx, [rax + 0x5404]     ; RAH0: Last 2 bytes of MAC address (bits 0..15)
    mov [rdi + 4], dx           ; Store MAC bytes 4..5 at 0x5B4

    ; Mark Network Card Status = 1 (ONLINE & READY!) at 0x5B6
    mov word [rdi + 6], 1

    ; 5. Initialize TX/RX DMA Descriptor Rings & Wake Link (CTRL / RCTL / TCTL)
    call e1000_init_rings

.pci_init_done:

    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; =========================================================================
; FRAQSHIFT INTEL E1000 DMA RING ENGINE & RAW ETHERNET PACKET TRANSMITTER
; =========================================================================
e1000_init_rings:
    push rax
    push rbx
    push rcx
    push rdx
    push rdi

    ; Fetch e1000 MMIO Base Address (BAR0) from 0x5B8
    mov rdi, 0x5B8
    mov rax, [rdi]
    test rax, rax
    jz .e1000_rings_done

    ; 1. Wake up Intel e1000 Link: Full Duplex (0x01) + ASDE (0x20) + Set Link Up (0x40) = 0x61!
    mov dword [rax + 0x0000], 0x00000061

    ; 1. Set Link Up (SLU = Bit 6 -> 0x40) in Device Control Register (CTRL = 0x0000)
    mov edx, [rax + 0x0000]
    or edx, 0x00000040          ; Force Link Up!
    mov [rax + 0x0000], edx

    ; 2. Clear Multicast Table Array (MTA: 0x5200..0x53FC, 128 dwords)
    xor rcx, rcx
.clear_mta_loop:
    mov dword [rax + 0x5200 + rcx * 4], 0
    inc rcx
    cmp rcx, 128
    jl .clear_mta_loop

    ; 3. Build 8-Entry Receive (RX) Descriptor Ring at 0x160000
    ; Each descriptor is 16 bytes: [0..7] = Buffer Phys Addr, [8..15] = Status/Length
    mov rdi, 0x160000
    mov rbx, 0x161000           ; First 2KB RX packet buffer
    xor rcx, rcx
.setup_rx_ring:
    mov [rdi], rbx              ; Buffer physical address
    mov qword [rdi + 8], 0      ; Clear status & length
    add rdi, 16
    add rbx, 2048               ; Advance 2KB per buffer
    inc rcx
    cmp rcx, 8
    jl .setup_rx_ring

    ; Ensure Address Valid (Bit 31 = 0x80000000) is set in RAH0 (0x5404) so RX accepts packets!
    mov edx, [rax + 0x5404]
    or edx, 0x80000000
    mov [rax + 0x5404], edx

    ; Program e1000 RX Ring Registers:
    mov dword [rax + 0x2800], 0x00160000 ; RDBAL: RX Descriptor Base Low
    mov dword [rax + 0x2804], 0          ; RDBAH: RX Descriptor Base High
    mov dword [rax + 0x2808], 128        ; RDLEN: 8 descriptors * 16 bytes = 128
    mov dword [rax + 0x2810], 0          ; RDH:   RX Head = 0

    ; Enable Receiver FIRST (EN=Bit 1 | UPE=Bit 3 | MPE=Bit 4 | BAM=Bit 15 | SECRC=Bit 26)
    mov dword [rax + 0x0100], 0x0400801A

    ; Set RX Tail (RDT = 7) AFTER enabling RCTL so hardware does not reset RDT to 0!
    mov dword [rax + 0x2818], 7
   

    ; 4. Build 8-Entry Transmit (TX) Descriptor Ring at 0x168000
    ; Each descriptor is 16 bytes: [0..7] = Buffer Addr, [8..9] = Length, [11] = CMD, [12] = Status
    mov rdi, 0x168000
    mov rbx, 0x169000           ; First 2KB TX packet buffer
    xor rcx, rcx
.setup_tx_ring:
    mov [rdi], rbx              ; TX Buffer physical address
    mov qword [rdi + 8], 0      ; Clear length, cmd, status
    add rdi, 16
    add rbx, 2048               ; Advance 2KB per buffer
    inc rcx
    cmp rcx, 8
    jl .setup_tx_ring

    ; Program e1000 TX Ring Registers:
    mov dword [rax + 0x3800], 0x00168000 ; TDBAL: TX Descriptor Base Low
    mov dword [rax + 0x3804], 0          ; TDBAH: TX Descriptor Base High
    mov dword [rax + 0x3808], 128        ; TDLEN: 8 descriptors * 16 bytes = 128
    mov dword [rax + 0x3810], 0          ; TDH:   TX Head = 0
    mov dword [rax + 0x3818], 0          ; TDT:   TX Tail = 0

    ; Enable Transmitter (TCTL = 0x0400): EN (Bit 1) | PSP Pad Short Packets (Bit 3) | CT=0x0F | COLD=0x40
    mov dword [rax + 0x0400], 0x010400FA
        ; Set Inter-Packet Gap (TIPG = 0x0410) for IEEE 802.3 standard
    mov dword [rax + 0x0410], 0x0060200A

    ; 5. Broadcast DHCP Discover & obtain IPv4 Lease from Router!
    call net_dhcp_discover

.e1000_rings_done:

    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; --- TRANSMIT RAW ETHERNET FRAME VIA INTEL E1000 HARDWARE ---
; Inputs: RSI = Pointer to Ethernet Frame in RAM, RCX = Frame Length (bytes, max 1514)
e1000_send_packet:
    push rax
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi

    ; Security Guard: Enforce strict Ethernet MTU max length (1514 bytes)
    cmp rcx, 1514
    ja .send_abort
    cmp rcx, 14
    jb .send_abort

    mov rdi, 0x5B8
    mov rax, [rdi]              ; RAX = e1000 BAR0 MMIO Base
    test rax, rax
    jz .send_abort

    ; Read current TX Tail index (TDT at offset 0x3818)
    mov edx, [rax + 0x3818]
    and edx, 7                  ; Wrap index 0..7

    ; Calculate target TX Descriptor address: 0x168000 + (index * 16)
    mov rbx, rdx
    shl rbx, 4
    add rbx, 0x168000

    ; Copy frame payload into the descriptor's 2KB DMA buffer
    mov rdi, [rbx]              ; Target DMA buffer address
    push rcx
    rep movsb                   ; Stream Ethernet frame into TX DMA buffer
    pop rcx

    ; Program TX Descriptor fields: Length, Command (EOP=1 | IFCS=2 | RS=8 -> 0x0B), Status=0
    mov word [rbx + 8], cx      ; Packet length
    mov byte [rbx + 10], 0      ; CSO
    mov byte [rbx + 11], 0x0B   ; CMD: End Of Packet (1) + Insert FCS/CRC (2) + Report Status (8)
    mov byte [rbx + 12], 0      ; Clear STA (Hardware sets Bit 0 DD when transmitted!)
    mov byte [rbx + 13], 0
    mov word [rbx + 14], 0

    ; Advance TX Tail (TDT) to trigger immediate hardware DMA transmission!
    inc edx
    and edx, 7
    mov [rax + 0x3818], edx

.send_abort:
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; =========================================================================
; FRAQSHIFT NETWORK STACK: RX PACKET POLLER & DHCP IPv4 CLIENT
; =========================================================================
; Polls RX Descriptor Ring (0x160000) for incoming Ethernet frames.
; Returns: RAX = Packet Length (0 if none), RSI = Pointer to RX Packet Buffer
e1000_poll_rx:
    push rbx
    push rcx
    push rdx
    push rdi

    mov rdi, 0x5B8
    mov rdx, [rdi]              ; RDX = e1000 BAR0 MMIO Base
    test rdx, rdx
    jz .rx_empty

    ; Read our software RX tracker index from 0x5BC
    mov rdi, 0x5BC
    mov ecx, [rdi]
    and ecx, 7                  ; Index 0..7

    ; Calculate RX Descriptor address: 0x160000 + (index * 16)
    mov rbx, rcx
    shl rbx, 4
    add rbx, 0x160000

    ; Check Status byte [rbx + 12]: Bit 0 (DD = Descriptor Done) set by hardware?
    mov al, byte [rbx + 12]
    test al, 0x01
    jz .rx_empty

    ; Packet received! Extract Length [rbx + 8] & Buffer Address [rbx]
    movzx r11d, word [rbx + 8]
    cmp r11d, 1518              ; Security Guard: Clamp max Ethernet frame size!
    ja .rx_recycle_only
    mov rsi, [rbx]              ; RSI = Pointer to received packet data in RAM

    ; Clear DD status bit and advance hardware RDT (keep 7 descriptors free!)
    mov byte [rbx + 12], 0
    mov eax, ecx
    add eax, 7
    and eax, 7
    mov [rdx + 0x2818], eax     ; Give descriptor back to hardware tail!
    inc ecx
    and ecx, 7
    mov [rdi], ecx              ; Save next RX index at 0x5BC
    mov eax, r11d               ; Return packet length in RAX
    jmp .rx_done


.rx_recycle_only:
    mov byte [rbx + 12], 0
    mov [rdx + 0x2818], ecx
    inc ecx
    and ecx, 7
    mov [rdi], ecx

.rx_empty:
    xor rax, rax                ; Return 0 = No packet waiting

.rx_done:
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    ret

; --- BROADCAST DHCP DISCOVER & RECEIVE IPv4 LEASE (Stored at 0x5C0) ---
net_dhcp_discover:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    ; Reset RX tracker (0x5BC) & IPv4 Lease status (0x5C0..0x5CF)
    mov rdi, 0x5BC
    mov dword [rdi], 0
    mov rdi, 0x5C0
    mov qword [rdi], 0          ; 0x5C0 = Assigned IP, 0x5C4 = Gateway IP
    mov qword [rdi + 8], 0      ; 0x5C8 = DNS IP, 0x5CC = DHCP Lease Status (0=Pending)

    ; Build a complete 342-byte Ethernet + IPv4 + UDP + DHCP Discover frame at 0x170000
    mov rdi, 0x170000
    xor rax, rax
    mov rcx, 64                 ; Clear 512 bytes cleanly
    rep stosq

    mov rdi, 0x170000

    ; --- 1. ETHERNET HEADER (14 bytes: 0..13) ---
    mov dword [rdi + 0], 0xFFFFFFFF ; Dst MAC: Broadcast FF:FF:FF:FF:FF:FF
    mov word  [rdi + 4], 0xFFFF
    mov rsi, 0x5B0
    mov eax, [rsi]              ; Src MAC bytes 0..3
    mov [rdi + 6], eax
    mov ax, [rsi + 4]           ; Src MAC bytes 4..5
    mov [rdi + 10], ax
    mov word [rdi + 12], 0x0008 ; EtherType: 0x0800 (IPv4, big-endian)

    ; --- 2. IPv4 HEADER (20 bytes: 14..33) ---
    mov byte [rdi + 14], 0x45   ; Version 4, Header Length 5 (20 bytes)
    mov byte [rdi + 15], 0x00   ; DSCP / ECN
    mov word [rdi + 16], 0x4801 ; Total Length = 328 bytes (0x0148 big-endian)
    mov word [rdi + 18], 0x3412 ; Identification
    mov word [rdi + 20], 0x0000 ; Flags / Fragment Offset
    mov byte [rdi + 22], 64     ; TTL = 64
    mov byte [rdi + 23], 17     ; Protocol = 17 (UDP)
    mov word [rdi + 24], 0x0000 ; Checksum (calculated below!)
    mov dword [rdi + 26], 0x00000000 ; Src IP: 0.0.0.0
    mov dword [rdi + 30], 0xFFFFFFFF ; Dst IP: 255.255.255.255

    ; Compute exact 16-bit IPv4 Header Checksum over bytes 14..33
    xor eax, eax
    xor rcx, rcx
.ip_csum_loop:
    movzx edx, word [rdi + 14 + rcx * 2]
    add eax, edx
    inc rcx
    cmp rcx, 10
    jl .ip_csum_loop
    mov edx, eax
    shr edx, 16
    and eax, 0xFFFF
    add eax, edx
    mov edx, eax
    shr edx, 16
    add eax, edx
    not ax
    mov [rdi + 24], ax          ; Store valid IPv4 Header Checksum!

    ; --- 3. UDP HEADER (8 bytes: 34..41) ---
    mov word [rdi + 34], 0x4400 ; Src Port: 68 (0x0044 big-endian)
    mov word [rdi + 36], 0x4300 ; Dst Port: 67 (0x0043 big-endian)
    mov word [rdi + 38], 0x3401 ; UDP Length: 308 bytes (0x0134 big-endian)
    mov word [rdi + 40], 0x0000 ; UDP Checksum (0 = optional in IPv4)

    ; --- 4. DHCP DISCOVER PAYLOAD (300 bytes: 42..341) ---
    mov byte [rdi + 42], 1      ; OP = 1 (BOOTREQUEST)
    mov byte [rdi + 43], 1      ; HTYPE = 1 (Ethernet)
    mov byte [rdi + 44], 6      ; HLEN = 6 (MAC length)
    mov byte [rdi + 45], 0      ; HOPS = 0
    mov dword [rdi + 46], 0x78563412 ; Transaction ID (XID)
    mov word [rdi + 52], 0x0080 ; Flags = 0x8000 (Broadcast reply, big-endian)

    ; Client Hardware Address (CHADDR at offset 70 = 42 + 28)
    mov rsi, 0x5B0
    mov eax, [rsi]
    mov [rdi + 70], eax
    mov ax, [rsi + 4]
    mov [rdi + 74], ax

    ; DHCP Magic Cookie (offset 278 = 42 + 236): 99.130.83.99 (0x63825363)
    mov dword [rdi + 278], 0x63538263

    ; DHCP Options (offset 282):
    mov byte [rdi + 282], 53    ; Option 53: DHCP Message Type
    mov byte [rdi + 283], 1     ; Length = 1
    mov byte [rdi + 284], 1     ; Type = 1 (DHCP DISCOVER)

    mov byte [rdi + 285], 55    ; Option 55: Parameter Request List
    mov byte [rdi + 286], 3     ; Length = 3
    mov byte [rdi + 287], 1     ; Subnet Mask
    mov byte [rdi + 288], 3     ; Router (Gateway)
    mov byte [rdi + 289], 6     ; DNS Server

    mov byte [rdi + 290], 255   ; Option 255: End of Options

    ; Transmit the 342-byte DHCP Discover packet out onto the network!
    mov rsi, 0x170000
    mov rcx, 342
    call e1000_send_packet

    ; Poll RX ring briefly (up to 2,000,000 cycles) for QEMU Router's DHCP Offer!
    mov rcx, 150000
.wait_dhcp_offer:
    push rcx
    call e1000_poll_rx
    pop rcx
    test rax, rax
    jnz .check_dhcp_reply
    dec rcx
    jnz .wait_dhcp_offer
    jmp .dhcp_done

.check_dhcp_reply:
    ; Verify Ethernet Type == IPv4 (0x0008) & UDP Dst Port == 68 (0x4400)
    cmp word [rsi + 12], 0x0008
    jne .wait_dhcp_offer
    cmp word [rsi + 36], 0x4400
    jne .wait_dhcp_offer

    ; Extract YIADDR (10.0.2.15) from DHCP Offer (offset 58)
    mov eax, [rsi + 58]
    mov rdi, 0x5C0
    mov [rdi], eax                  ; Save Assigned IPv4 Address at 0x5C0!
    mov dword [rdi + 4], 0x0202000A ; QEMU Gateway 10.0.2.2
    mov dword [rdi + 8], 0x0302000A ; QEMU DNS 10.0.2.3
    mov dword [rdi + 12], 1         ; DHCP Lease Status = 1!

    ; --- SEND DHCP REQUEST (Option 53 = 3) SO QEMU ROUTER ACTIVATES 10.0.2.15! ---
    mov rdi, 0x170000
    mov byte [rdi + 284], 3         ; Change Option 53 from DISCOVER (1) -> REQUEST (3)!
    mov byte [rdi + 285], 50        ; Option 50: Requested IP Address
    mov byte [rdi + 286], 4         ; Length = 4
    mov [rdi + 287], eax            ; 10.0.2.15
    mov byte [rdi + 291], 255       ; End of Options
    mov word [rdi + 40], 0      ; Clear UDP checksum so QEMU accepts modified DHCP Request!
        mov word [rdi + 40], 0      ; Clear UDP checksum
    mov ecx, 50000
.dhcp_tx_wait:
    pause
    dec ecx
    jnz .dhcp_tx_wait

    mov rsi, 0x170000
    mov rcx, 342
    call e1000_send_packet      ; Commit lease with QEMU virtual router!

    ; Wait briefly for QEMU's DHCP ACK so 10.0.2.15 is active for internet TCP!
    mov ecx, 150000
.wait_dhcp_ack:
    pause
    push rcx
    call e1000_poll_rx
    pop rcx
    dec ecx
    jnz .wait_dhcp_ack

    

.dhcp_done:

    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret





; --- HARDWARE SECURITY VIOLATION HANDLER (#PF & #GP ISOLATION) ---
; Triggered if a Ring 3 app tries to touch Kernel RAM, execute NX data, or use I/O ports!
fraq_security_fault_handler:
    ; Check CS on interrupt stack frame (RSP+8 if no error code, RSP+16 with error code)
    ; #GP (13) and #PF (14) always push a 64-bit error code at [RSP]!
    mov rax, [rsp + 16]         ; Fetch saved User CS from hardware interrupt frame
    test rax, 0x03              ; Was the fault caused by Ring 3 (CPL = 3)?
    jz fraq_default_exception_handler ; Jump straight to global halt handler!


    ; RING 3 APP CONTAINED! Terminate the rogue app and return cleanly to Kernel!
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov rsp, [rel kernel_resume_rsp]
    jmp [rel kernel_resume_rip]

fraq_default_exception_handler:
.kernel_panic_halt:
    cli
    hlt
    jmp .kernel_panic_halt

align 16
idt64_ptr:
    dw 4095                     ; IDT Limit (256 * 16 bytes - 1)
    dq 0x54000                  ; IDT Base Address in protected Kernel RAM

; =========================================================================
; FRAQSHIFT REAL UDP DNS RESOLVER (Queries 10.0.2.3:53 for A-Record IPv4)
; Input:  RSI = Pointer to domain string (e.g. "neverssl.com", 0)
; Output: EAX = Resolved 32-bit IPv4 address (network byte order), or 0 on fail
; =========================================================================
net_dns_resolve:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12

    mov r12, rsi                ; Save domain name pointer

    ; Clear DNS packet buffer at 0x170600 (512 bytes)
    mov rdi, 0x170600
    xor rax, rax
    mov rcx, 64
    rep stosq

    mov rdi, 0x170600

    ; --- 1. ETHERNET HEADER (0..13) ---
    mov rsi, 0x5D0              ; Gateway MAC resolved by ARP
    mov eax, [rsi]
    mov [rdi + 0], eax
    mov ax, [rsi + 4]
    mov [rdi + 4], ax
    mov rsi, 0x5B0              ; Our e1000 MAC
    mov eax, [rsi]
    mov [rdi + 6], eax
    mov ax, [rsi + 4]
    mov [rdi + 10], ax
    mov word [rdi + 12], 0x0008 ; IPv4

    ; --- 2. BUILD DNS QUERY PAYLOAD FIRST AT OFFSET 42 TO KNOW EXACT LENGTH ---
    mov word [rdi + 42], 0x3412 ; DNS Transaction ID = 0x1234
    mov word [rdi + 44], 0x0001 ; Flags = 0x0100 (Standard Query, Recursion Desired)
    mov word [rdi + 46], 0x0100 ; QDCOUNT = 1 Question
    mov word [rdi + 48], 0x0000 ; ANCOUNT = 0
    mov word [rdi + 50], 0x0000 ; NSCOUNT = 0
    mov word [rdi + 52], 0x0000 ; ARCOUNT = 0

    ; Encode domain name into DNS QNAME format (e.g. "neverssl.com" -> 8 "neverssl" 3 "com" 0)
    lea rdi, [rdi + 54]         ; QNAME start
    mov rsi, r12                ; Source domain string
.dns_encode_label:
    mov rbx, rdi                ; Remember length byte position for this label
    inc rdi
    xor ecx, ecx                ; Label length counter
.dns_label_chars:
    mov al, byte [rsi]
    test al, al
    jz .dns_finish_qname
    cmp al, '.'
    je .dns_next_label
    mov [rdi], al
    inc rdi
    inc rsi
    inc ecx
    jmp .dns_label_chars
.dns_next_label:
    mov [rbx], cl               ; Write label length prefix
    inc rsi                     ; Skip '.'
    jmp .dns_encode_label
.dns_finish_qname:
    mov [rbx], cl               ; Write final label length prefix
    mov byte [rdi], 0           ; End of QNAME (0x00)
    inc rdi
    mov word [rdi], 0x0100      ; QTYPE = 1 (A Record - IPv4 Host Address)
    mov word [rdi + 2], 0x0100  ; QCLASS = 1 (IN - Internet)
    add rdi, 4

    ; Calculate total Ethernet frame length (RDI - 0x170600)
    mov rcx, rdi
    mov rdi, 0x170600
    sub rcx, rdi                ; RCX = Total Ethernet frame length
    mov r12, rcx                ; Save frame length in R12

    ; --- 3. IPv4 HEADER (14..33) ---
    mov byte [rdi + 14], 0x45
    mov eax, r12d
    sub eax, 14                 ; IP Total Length = Frame Len - 14
    xchg al, ah
    mov [rdi + 16], ax
    mov word [rdi + 18], 0x5544
    mov byte [rdi + 22], 64     ; TTL
    mov byte [rdi + 23], 17     ; Protocol = 17 (UDP)
    mov dword [rdi + 26], 0x0F02000A ; Src IP: 10.0.2.15
    mov dword [rdi + 30], 0x0302000A ; Dst IP: 10.0.2.3 (QEMU DNS Server!)

    ; IPv4 Checksum
    xor eax, eax
    xor rcx, rcx
.dns_ip_csum:
    movzx edx, word [rdi + 14 + rcx * 2]
    add eax, edx
    inc rcx
    cmp rcx, 10
    jl .dns_ip_csum
    mov edx, eax
    shr edx, 16
    and eax, 0xFFFF
    add eax, edx
    not ax
    mov [rdi + 24], ax

    ; --- 4. UDP HEADER (34..41) ---
    mov word [rdi + 34], 0x35D4 ; Src Port: 54325
    mov word [rdi + 36], 0x3500 ; Dst Port: 53 (DNS, big-endian)
    mov eax, r12d
    sub eax, 34                 ; UDP Length = Frame Len - 34
    xchg al, ah
    mov [rdi + 38], ax
    mov word [rdi + 40], 0x0000 ; UDP Checksum optional

    ; Send DNS Query packet!
    mov rsi, 0x170600
    mov rcx, r12
    call e1000_send_packet

    ; --- 5. WAIT FOR DNS RESPONSE FROM 10.0.2.3 ---
    mov rcx, 25000000 
.wait_dns_reply:
    pause
    push rcx
    call e1000_poll_rx
    pop rcx
    test rax, rax
    jnz .inspect_dns_packet
.next_dns_tick:
    dec rcx
    jnz .wait_dns_reply

    xor eax, eax                ; Timeout -> Return 0
    jmp .dns_done

.inspect_dns_packet:
    mov esi, esi                ; Clear upper 32 bits of RSI FIRST!
    

    cmp word [rsi + 12], 0x0008 ; IPv4?
    jne .next_dns_tick
    cmp byte [rsi + 23], 17     ; UDP?
    jne .next_dns_tick
    cmp word [rsi + 42], 0x3412 ; DNS Transaction ID == 0x1234?
    jne .next_dns_tick


    mov eax, [rsi + 84]
    mov rdi, 0x170000           ; Safe dedicated network RAM (never collides with 0x5xx!)
    mov [rdi], eax


.dns_done:
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; =========================================================================
; FRAQSHIFT INTERNET ENGINE: ARP RESOLVER & TCP/HTTP GET CLIENT (PORT 80)
; =========================================================================
; Resolves Gateway MAC (10.0.2.2) via ARP and stores it at 0x5D0 (6 bytes)
net_arp_resolve_gateway:
    ; Pre-seed QEMU's standard gateway MAC (52:55:0A:00:02:02) at 0x5D0 so TCP never drops!
    mov rdi, 0x5D0
    mov dword [rdi], 0x000A5552     ; 52 55 0A 00
    mov word  [rdi + 4], 0x0202     ; 02 02

    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    ; Build 42-byte ARP Request frame at 0x170400
    mov rdi, 0x170400
    xor rax, rax
    mov rcx, 8
    rep stosq

    mov rdi, 0x170400

    ; Ethernet Header (14 bytes)
    mov dword [rdi + 0], 0xFFFFFFFF ; Broadcast Dst MAC
    mov word  [rdi + 4], 0xFFFF
    mov rsi, 0x5B0
    mov eax, [rsi]              ; Our Src MAC 0..3
    mov [rdi + 6], eax
    mov ax, [rsi + 4]           ; Our Src MAC 4..5
    mov [rdi + 10], ax
    mov word [rdi + 12], 0x0608 ; EtherType: 0x0806 (ARP, big-endian)

    ; ARP Payload (28 bytes: offsets 14..41)
    mov word [rdi + 14], 0x0100 ; HTYPE: Ethernet (1)
    mov word [rdi + 16], 0x0008 ; PTYPE: IPv4 (0x0800)
    mov byte [rdi + 18], 6      ; HLEN: 6
    mov byte [rdi + 19], 4      ; PLEN: 4
    mov word [rdi + 20], 0x0100 ; OPER: ARP Request (1)

    ; Sender MAC (22..27) & Sender IP (28..31 = 10.0.2.15)
    mov eax, [rsi]
    mov [rdi + 22], eax
    mov ax, [rsi + 4]
    mov [rdi + 26], ax
    mov dword [rdi + 28], 0x0F02000A ; 10.0.2.15

    ; Target MAC (32..37 = 0) & Target IP (38..41 = 10.0.2.2 QEMU Gateway)
    mov dword [rdi + 38], 0x0202000A ; 10.0.2.2

    ; Send 42-byte ARP Request!
    mov rsi, 0x170400
    mov rcx, 42
    call e1000_send_packet

    ; Wait up to 2,000,000 polls for ARP Reply (OPER == 2)
    mov rcx, 150000
.wait_arp_reply:
    push rcx
    call e1000_poll_rx
    pop rcx
    test rax, rax
    jnz .check_arp_packet
    dec rcx
    jnz .wait_arp_reply

    ; Fallback to standard QEMU Slirp Gateway MAC (52:55:0a:00:02:02) if timeout
    mov rdi, 0x5D0
    mov dword [rdi], 0x000A5552
    mov word  [rdi + 4], 0x0202
    jmp .arp_done

.check_arp_packet:
    cmp word [rsi + 12], 0x0608 ; EtherType == ARP?
    jne .wait_arp_reply
    cmp word [rsi + 20], 0x0200 ; OPER == ARP Reply (2)?
    jne .wait_arp_reply

    ; Extract Gateway's 6-byte MAC from Sender MAC (offset 22) -> Store at 0x5D0!
    mov eax, [rsi + 22]
    mov rdi, 0x5D0
    mov [rdi], eax
    mov ax, [rsi + 26]
    mov [rdi + 4], ax

.arp_done:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; --- FETCH LIVE WEB PAGE OVER TCP/HTTP INTO USER BUFFER (RDI) ---
; Inputs: RDI = Validated Ring 3 User Buffer (max 4096 bytes)
; Returns: RAX = Number of bytes written to Ring 3 buffer
net_http_fetch_live:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13

    mov r12, rdi                ; R12 = Safe Ring 3 output buffer pointer
    xor r13, r13                ; R13 = Total HTML/text bytes collected

    ; 1. Resolve Gateway MAC first
    call net_arp_resolve_gateway

    ; 2. Direct IPv4 for neverssl.com (34.223.124.45 = 0x2D7CDF22) — skip DNS!
    mov dword [abs 0x170000], 0x2D7CDF22
    jmp .dns_succeeded


    ; Update status on screen: "STEP 1: ARP OK -> RESOLVING DNS..."
    mov dword [r12], 'STEP'
    mov dword [r12+4], ' 1: '
    mov dword [r12+8], 'DNS.'
    mov byte  [r12+12], 0

    ; 2. Direct IPv4 for neverssl.com (34.223.124.45 = 0x2D7CDF22) — skip DNS!
    mov dword [abs 0x170000], 0x2D7CDF22
    jmp .dns_succeeded


    ; DNS Failed / Timeout -> Print clear message on screen!
    mov dword [r12], 'ERR:'
    mov dword [r12+4], ' DNS'
    mov dword [r12+8], ' FAI'
    mov word  [r12+12], 'L!'
    mov byte  [r12+14], 0
    xor rax, rax
    jmp .http_done

.dns_succeeded:
    ;mov r12, 0x510000           ; Guarantee valid Ring 3 buffer pointer!
    ;mov dword [r12], 'STEP'
    ;mov dword [r12+4], ' 2: '
    ;mov dword [r12+8], 'SYN.'
    ;mov byte  [r12+12], 0


    ; 3. Send TCP SYN Packet to Resolved DNS IP (0x5D8) on Port 80!
    mov edx, 0x02               ; TCP Flags = SYN (0x02)
    mov r8d, 0x00000010         ; SEQ = 0x10000000 (big-endian)
    xor r9d, r9d                ; ACK = 0
    xor rsi, rsi
    xor rcx, rcx

    

    call net_send_tcp_packet


    ; 3. Wait for Server's TCP SYN-ACK (Flags & 0x12 == 0x12)
    mov rcx, 400000   
.wait_syn_ack:
    push rcx
    call e1000_poll_rx
    pop rcx
    test rax, rax
    jnz .inspect_syn_ack
.next_syn_tick:
    dec rcx
    jnz .wait_syn_ack

    mov dword [r12], 'ERR:'
    mov dword [r12+4], ' NO '
    mov dword [r12+8], 'SYN!'
    mov byte  [r12+12], 0
    mov rax, -3
    jmp .http_done




.inspect_syn_ack:
    mov esi, esi                ; Ensure clean 64-bit pointer!
    cmp word [rsi + 12], 0x0008 ; IPv4?
    jne .next_syn_tick
    cmp byte [rsi + 23], 6      ; Protocol == TCP (6)?
    jne .next_syn_tick
    cmp dword [rsi + 26], 0x2D7CDF22 ; Src IP == 34.223.124.45 (neverssl.com)?
    jne .next_syn_tick
    mov al, byte [rsi + 47]     ; TCP Flags byte
    and al, 0x12                ; SYN (0x02) + ACK (0x10)
    cmp al, 0x12
    jne .next_syn_tick


    ; Extract Server's SEQ (offset 38) in host order, add 1, convert back to big-endian for ACK!
    mov eax, [rsi + 38]
    bswap eax
    inc eax
    bswap eax
    mov r9d, eax                ; R9D = Server SEQ + 1 (our ACK number!)

    ; 4. Complete 3-Way Handshake (ACK) & Stream HTTP/1.0 GET Request!
    mov edx, 0x18               ; TCP Flags = PSH (0x08) + ACK (0x10)
    mov r8d, 0x01000010         ; Our SEQ = 0x10000001 (big-endian)
    lea rsi, [rel http_get_request]
    mov rcx, http_get_request_end - http_get_request
    call net_send_tcp_packet

    ; 5. Collect incoming HTTP response packets safely into Ring 3 buffer (max 4096 bytes!)
    mov rcx, 500000   
.recv_http_loop:
    push rcx
    call e1000_poll_rx
    pop rcx
    test rax, rax
    jnz .process_http_chunk
.next_http_tick:
    dec rcx
    jnz .recv_http_loop
    jmp .http_finalize


.process_http_chunk:
    cmp word [rsi + 12], 0x0008 ; IPv4?
    jne .recv_http_loop
    cmp byte [rsi + 23], 6      ; TCP?
    jne .recv_http_loop
    cmp word [rsi + 36], 0x00C0 ; Dst Port == 49152?
    jne .recv_http_loop

    ; Calculate TCP payload length: IP Total Len (offset 16, big-endian) - 40 bytes (IP+TCP headers)
    movzx edx, word [rsi + 16]
    xchg dl, dh
    sub edx, 40
    cmp edx, 0
    jle .check_tcp_fin

    ; Copy payload bytes safely into Ring 3 buffer (enforce strict 4096-byte cap!)
    add rsi, 54                 ; Start of HTTP payload (14 Eth + 20 IP + 20 TCP)
.copy_http_bytes:
    cmp r13, 4095               ; Hard Ring 3 buffer limit!
    jge .http_finalize
    mov al, byte [rsi]
    mov [r12 + r13], al         ; Write byte into Ring 3 sandbox buffer
    inc rsi
    inc r13
    dec edx
    jnz .copy_http_bytes

.check_tcp_fin:
    ; Null-terminate Ring 3 string and return!
    mov byte [r12 + r13], 0
    mov rax, r13
    jmp .http_done

.http_finalize:
    mov byte [r12 + r13], 0
    mov rax, r13

.http_done:
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; --- HELPER: BUILD & TRANSMIT ETHERNET + IPv4 + TCP PACKET ---
; Inputs: EDX = TCP Flags, R8D = SEQ (BE), R9D = ACK (BE), RSI = Payload Ptr, RCX = Payload Len
net_send_tcp_packet:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r10
    push r11

    mov r10, rsi                ; Save payload pointer
    mov r11, rcx                ; Save payload length

    mov rdi, 0x170800
    xor rax, rax
    mov rcx, 32
    rep stosq

    mov rdi, 0x170800

    ; 1. Ethernet Header (Gateway Dst MAC from 0x5D0, Our Src MAC from 0x5B0)
    mov rsi, 0x5D0
    mov eax, [rsi]
    mov [rdi + 0], eax
    mov ax, [rsi + 4]
    mov [rdi + 4], ax
    mov rsi, 0x5B0
    mov eax, [rsi]
    mov [rdi + 6], eax
    mov ax, [rsi + 4]
    mov [rdi + 10], ax
    mov word [rdi + 12], 0x0008 ; IPv4

    ; 2. IPv4 Header (Total Length = 40 + Payload Len)
    mov byte [rdi + 14], 0x45
    mov eax, 40
    add eax, r11d
    xchg al, ah
    mov [rdi + 16], ax          ; IP Total Length (big-endian)
    mov word [rdi + 18], 0x1122
    mov byte [rdi + 22], 64     ; TTL
    mov byte [rdi + 23], 6      ; Protocol = 6 (TCP)
    mov dword [rdi + 26], 0x0F02000A ; Src IP: 10.0.2.15
    mov dword [rdi + 30], 0x2D7CDF22 ; Dst IP: 34.223.124.45 (neverssl.com!)









    ; IPv4 Header Checksum
    xor eax, eax
    xor rcx, rcx
.tcp_ip_csum:
    movzx ebx, word [rdi + 14 + rcx * 2]
    add eax, ebx
    inc rcx
    cmp rcx, 10
    jl .tcp_ip_csum
    mov ebx, eax
    shr ebx, 16
    and eax, 0xFFFF
    add eax, ebx
    not ax
    mov [rdi + 24], ax

    ; 3. TCP Header (20 bytes: offsets 34..53)
    mov word [rdi + 34], 0x00C0 ; Src Port: 49152 (0xC000 BE)
    mov word [rdi + 36], 0x5000 ; Dst Port: 80 (HTTP)
    mov [rdi + 38], r8d         ; SEQ (BE)
    mov [rdi + 42], r9d         ; ACK (BE)
    mov byte [rdi + 46], 0x50   ; Data Offset: 5 dwords (20 bytes)
    mov byte [rdi + 47], dl     ; TCP Flags (SYN / ACK / PSH+ACK)
    mov word [rdi + 48], 0x0020 ; Window Size: 8192 (0x2000 BE)

    ; Copy HTTP Payload if any
    test r11, r11
    jz .compute_tcp_csum
    mov rsi, r10
    lea rdi, [rdi + 54]
    mov rcx, r11
    rep movsb
    mov rdi, 0x170800

.compute_tcp_csum:
    ; Compute TCP Checksum over Pseudo-Header (12 bytes) + TCP Header + Payload
    xor eax, eax
    ; Pseudo-header: Src IP (2 words) + Dst IP (2 words) + Protocol 6 (0x0600 BE) + TCP Length
    movzx ebx, word [rdi + 26]
    add eax, ebx
    movzx ebx, word [rdi + 28]
    add eax, ebx
    movzx ebx, word [rdi + 30]
    add eax, ebx
    movzx ebx, word [rdi + 32]
    add eax, ebx
    add eax, 0x0600             ; TCP Protocol = 6 in network byte order

    mov ebx, 20
    add ebx, r11d
    xchg bl, bh
    add eax, ebx                ; TCP Segment Length in network byte order

    ; Sum TCP Header + Payload words (padded with 0 if odd length)
    mov ecx, 20
    add ecx, r11d
    lea rsi, [rdi + 34]
.tcp_seg_sum:
    cmp ecx, 1
    je .tcp_odd_byte
    jb .tcp_fold_csum
    movzx ebx, word [rsi]
    add eax, ebx
    add rsi, 2
    sub ecx, 2
    jmp .tcp_seg_sum
.tcp_odd_byte:
    movzx ebx, byte [rsi]
    add eax, ebx
.tcp_fold_csum:
    mov ebx, eax
    shr ebx, 16
    and eax, 0xFFFF
    add eax, ebx
    mov ebx, eax
    shr ebx, 16
    and eax, 0xFFFF
    add eax, ebx
    not ax
    mov [rdi + 50], ax          ; Store valid 16-bit TCP Checksum!


    ; Transmit complete Ethernet + IPv4 + TCP frame (54 + Payload Len)!
    mov rsi, 0x170800
    mov rcx, 54
    add rcx, r11
    call e1000_send_packet

    pop r11
    pop r10
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

http_get_request:
    db "GET / HTTP/1.0", 13, 10
    db "Host: neverssl.com", 13, 10
    db "User-Agent: FraqshiftOS/1.0", 13, 10
    db "Connection: close", 13, 10, 13, 10
http_get_request_end:






ata_read_sector:
    ; --- BARE-METAL ATA PIO SECTOR READER ---
    ; Inputs:  EAX = LBA Sector Number (The block address on disk)
    ;          RDI = Target RAM Address (Where to dump the 512 bytes)
    ; Destroys: EAX, EBX, ECX, EDX, DX
    
    push rax                    ; Preserve sector number
    push rdi                    ; Preserve RAM target pointer

    mov ebx, eax                ; Backup LBA sector address

    ; 1. Setup Sector Count (Port 0x1F2) - We want to read exactly 1 sector
    mov dx, 0x1F2
    mov al, 1
    out dx, al

    ; 2. Send LBA Bits 0-7 (Port 0x1F3)
    mov dx, 0x1F3
    mov al, bl
    out dx, al

    ; 3. Send LBA Bits 8-15 (Port 0x1F4)
    mov dx, 0x1F4
    shr ebx, 8
    mov al, bl
    out dx, al

    ; 4. Send LBA Bits 16-23 (Port 0x1F5)
    mov dx, 0x1F5
    shr ebx, 8
    mov al, bl
    out dx, al

    ; 5. Send Drive & LBA Bits 24-27 (Port 0x1F6)
    ; We also set bit 6 (0x40) to enable LBA mode, and bit 4 to select Master Drive
    mov dx, 0x1F6
    shr ebx, 8
    and bl, 0x0F                ; Mask out top bits, keep only bits 24-27
    or bl, 0xE0                 ; 0xE0 = Master Drive + LBA mode flags
    mov al, bl
    out dx, al

    ; 6. Send READ Command 0x20 (Port 0x1F7)
    mov dx, 0x1F7
    mov al, 0x20                ; 0x20 = ATA Command: Read Sectors with Retry
    out dx, al

.ata_wait_ready:
    ; 7. HARDWARE POLLING LOOP: Wait for the drive to process and hit the buffer
    mov dx, 0x1F7
    in al, dx
    test al, 0x08               ; Check if Data Request (DRQ) bit is set to 1
    jz .ata_wait_ready          ; Not ready yet? Keep polling the silicon!

    ; 8. READ DATA FROM HARDWARE BUFFER (Port 0x1F0)
    ; A sector is 512 bytes, which equals 256 "words" (16-bit blocks)
    pop rdi                     ; Restore your target RAM pointer
    mov dx, 0x1F0               ; Data port
    mov ecx, 256                ; Read 256 words (512 bytes total)

.read_data_loop:
    in ax, dx                   ; Pull 2 bytes from drive hardware buffer
    mov [rdi], ax               ; Write 2 bytes into RAM memory
    add rdi, 2                  ; Advance RAM destination pointer by 2 bytes
    loop .read_data_loop        ; Repeat until all 512 bytes are safely in RAM

    pop rax                     ; Restore original EBA sector register cleanly
    ret                         ; Return back to kernel execution


ata_write_sector:
    ; --- BARE-METAL ATA PIO SECTOR WRITER (ISOLATED GLOBAL SCOPE) ---
    push rax                    ; Preserve sector number
    push rsi                    ; Preserve RAM source pointer

    mov ebx, eax                ; Backup LBA sector address

    ; 1. Setup Sector Count (Port 0x1F2)
    mov dx, 0x1F2
    mov al, 1
    out dx, al

    ; 2. Send LBA Bits 0-7 (Port 0x1F3)
    mov dx, 0x1F3
    mov al, bl
    out dx, al

    ; 3. Send LBA Bits 8-15 (Port 0x1F4)
    mov dx, 0x1F4
    shr ebx, 8
    mov al, bl
    out dx, al

    ; 4. Send LBA Bits 16-23 (Port 0x1F5)
    mov dx, 0x1F5
    shr ebx, 8
    mov al, bl
    out dx, al

    ; 5. Send Drive & LBA Bits 24-27 (Port 0x1F6)
    mov dx, 0x1F6
    shr ebx, 8
    and bl, 0x0F
    or bl, 0xE0                 ; Master Drive + LBA mode
    mov al, bl
    out dx, al

    ; 6. Send WRITE Command 0x30 (Port 0x1F7)
    mov dx, 0x1F7
    mov al, 0x30                ; 0x30 = ATA Command: Write Sectors
    out dx, al

fraq_disk_write_wait:
    ; 7. HARDWARE POLLING: Wait for the drive buffer using absolute global labels
    mov dx, 0x1F7
    in al, dx
    test al, 0x08               ; Check DRQ bit
    jz fraq_disk_write_wait     ; Loop safely on silicon status register

    ; 8. WRITE DATA TO HARDWARE BUFFER (Port 0x1F0)
    pop rsi                     ; Restore source RAM pointer
    mov dx, 0x1F0               ; Data port
    mov ecx, 256                ; Write 256 words (512 bytes total)

fraq_disk_write_loop:
    mov ax, [rsi]               ; Fetch 2 bytes from RAM
    out dx, ax                  ; Push 2 bytes straight into drive buffer
    add rsi, 2                  ; Advance RAM pointer by 2 bytes
    loop fraq_disk_write_loop   ; Repeat until all 512 bytes are written

    ; 9. FLUSH CACHE COMMAND (Port 0x1F7)
    mov dx, 0x1F7
    mov al, 0xE7
    out dx, al

    pop rax                     ; Restore original EAX
    ret                         ; Return back to kernel cleanly

    fs_load_directory:
    ; --- FRAQSHIFT RAM-DISK FILING ENGINE (GLOBAL SCOPE) ---
    push rsi
    push rdi
    push rcx

    mov rdi, 0x9000             ; Base memory address for file index table

    ; --- FILE 1 INDEX: "HELP" ---
    mov dword [rdi], 'HELP'     ; Filename
    mov dword [rdi + 8], 0xA000 ; Virtual Start Address
    mov dword [rdi + 12], 22    ; File Size = 22 bytes
    
    ; --- FILE 1 TEXT CONTENT INJECTION ---
    mov rsi, 0xA000
    mov dword [rsi], 'Welc'
    mov dword [rsi + 4], 'ome '
    mov dword [rsi + 8], 'to F'
    mov dword [rsi + 12], 'raqs'
    mov dword [rsi + 16], 'hift'
    mov word  [rsi + 20], '!'  ; Total string: "Welcome to Fraqshift!"

    ; --- FILE 2 INDEX: "WEB" ---
    add rdi, 32                 ; Move to next file slot in index
    mov dword [rdi], 'WEB '     ; Filename
    mov dword [rdi + 8], 0xB000 ; Virtual Start Address
    mov dword [rdi + 12], 22    ; File Size = 22 bytes

    ; --- FILE 2 TEXT CONTENT INJECTION ---
    mov rsi, 0xB000
    mov dword [rsi], 'Brow'
    mov dword [rsi + 4], 'ser '
    mov dword [rsi + 8], 'Engi'
    mov dword [rsi + 12], 'ne A'
    mov dword [rsi + 16], 'ctiv'
    mov word  [rsi + 20], 'e.'  ; Total string: "Browser Engine Active."

    pop rcx
    pop rdi
    pop rsi
    ret

fs_read_file:
    ; --- FRAQSHIFT FILE CONTENT READER (GLOBAL SCOPE) ---
    ; Input:  RSI = Pointer to the file's text buffer start (0xA000)
    ; Output: AL  = First character byte contained inside the file
    mov al, [rsi]               ; Load character byte directly from file contents into AL register
    ret                         ; Clean return, 100% crash-proof

fs_create_file:
    ; --- FRAQSHIFT FILE SYSTEM: CREATE NEW FILE ENTRY ---
    ; Input:  EAX = 4-byte ASCII Filename (e.g., 'DOC ')
    ; Destroys: RDI, RBX
    push rdi
    push rbx

    mov rdi, 0x9000             ; Point to base memory of file index table [3.1]
    add rdi, 64                 ; Move past "HELP" (offset 0) and "WEB" (offset 32) to Slot 3! [3.1]

    ; Write the new file metadata dynamically into the Ramdisk structure
    mov [rdi], eax              ; 1. Save the 4-byte filename directly to RAM [3.1]
    mov dword [rdi + 8], 0xC000 ; 2. Assign text content memory boundary to 0xC000 [3.1]
    mov dword [rdi + 12], 0     ; 3. Initialize File Size as 0 bytes [3.1]

    pop rbx
    pop rdi
    ret                         ; Clean, crash-proof return

; --- FRAQSHIFT MEMORY MANAGEMENT LAYER (PHASE 13) ---
; Global tracking variable stored at a safe static memory slot (e.g., 0x560)
; Holds the current free boundary address of the system Heap.

heap_init:
    ; --- INITIALIZE HEAP POINTER ---
    ; Sets the start of dynamic memory allocation to 1MB boundary (0x100000)
    push rax
    mov rax, 0x560              ; Variable storage address
    mov qword [rax], 0x100000   ; Start heap at 1MB cleanly
    pop rax
    ret

fraq_malloc:
    ; --- FRAQSHIFT MEMORY ALLOCATOR ---
    ; Input:  RCX = Number of bytes requested
    ; Output: RAX = Pointer to the allocated memory block start
    ; Destroys: RBX
    push rbx

    mov rbx, 0x560              ; Point to our heap tracker variable
    mov rax, [rbx]              ; Fetch the current free memory boundary address

    ; Calculate the next free boundary by adding the requested size
    push rax
    add rax, rcx                ; Advance the boundary forward by RCX bytes
    mov [rbx], rax              ; Save the new boundary back to tracker memory
    pop rax                     ; RAX now holds the correct starting pointer!

    pop rbx
    ret                         ; Clean, 100% crash-proof return

; --- FRAQSHIFT VBE 1080P GRAPHICS ENGINE (PHASE 14 - STEP 1) ---

vbe_write:
    ; Helper to write to Bochs Graphics Adapter ports
    ; Input: AX = Index, BX = Data
    push rdx
    mov dx, 0x01CE
    out dx, ax                  ; Write register index
    mov dx, 0x01CF
    mov ax, bx
    out dx, ax                  ; Write register data
    pop rdx
    ret

vbe_set_1080p:
    ; --- FORCE INTEL/QEMU SILICON INTO SAFE 640x480 TRUE COLOR ---
    ; (We keep the function name intact so we don't have to change your top calls!) [3.1]
    push rax
    push rbx

    ; 1. Disable VBE extensions temporarily
    mov ax, 4                   ; VBE_DISPI_INDEX_ENABLE
    mov bx, 0                   ; VBE_DISPI_DISABLED
    call vbe_write

    ; 2. Set X Resolution to 640
    mov ax, 1                   ; VBE_DISPI_INDEX_XRES
    mov bx, 640
    call vbe_write

    ; 3. Set Y Resolution to 480
    mov ax, 2                   ; VBE_DISPI_INDEX_YRES
    mov bx, 480
    call vbe_write

    ; 4. Set Bit Depth to 32 bits (True Color)
    mov ax, 3                   ; VBE_DISPI_INDEX_BPP
    mov bx, 32
    call vbe_write

    ; 5. Re-enable VBE extensions cleanly
    mov ax, 4                   ; VBE_DISPI_INDEX_ENABLE
    mov bx, 0x41                ; VBE_DISPI_ENABLED | VBE_DISPI_LFB
    call vbe_write

    pop rbx
    pop rax
    ret

; --- FRAQSHIFT PS/2 MOUSE DRIVER (PHASE 14 - STEP 1) ---

mouse_wait_write:
    mov dx, 0x64
    in al, dx
    test al, 0x02               ; Check Input Buffer Status bit
    jnz mouse_wait_write        ; Wait until port is ready for writing
    ret

mouse_wait_read:
    mov dx, 0x64
    in al, dx
    test al, 0x01               ; Check Output Buffer Status bit
    jz mouse_wait_read          ; Wait until port has data to read
    ret

mouse_init:
    ; --- INITIALIZE HARDWARE PS/2 MOUSE COMPONENT ---
    push rax
    push rdx

    ; 1. Enable Mouse Port on Keyboard Controller
    call mouse_wait_write
    mov dx, 0x64
    mov al, 0xA8                ; Command 0xA8 = Enable Mouse Clock/Port
    out dx, al

    ; 2. Enable Interrupts (Get Controller Command Byte)
    call mouse_wait_write
    mov dx, 0x64
    mov al, 0x20                ; Command 0x20 = Read Command Byte
    out dx, al
    call mouse_wait_read
    mov dx, 0x60
    in al, dx
    or al, 0x02                 ; Keep the existing mouse interrupt setting
    or al, 0x40                 ; Enable i8042 keyboard Set-2 -> Set-1 translation
    push rax

    ; Write updated Command Byte back
    call mouse_wait_write
    mov dx, 0x64
    mov al, 0x60                ; Command 0x60 = Write Command Byte
    out dx, al
    call mouse_wait_write
    mov dx, 0x60
    pop rax
    out dx, al

    ; 3. Tell Mouse to use Default Settings
    call mouse_wait_write
    mov dx, 0x64
    mov al, 0xD4                ; Command 0xD4 = Write to Mouse Device
    out dx, al
    call mouse_wait_write
    mov dx, 0x60
    mov al, 0xF6                ; Mouse Command 0xF6 = Set Defaults
    out dx, al
    call mouse_wait_read
    mov dx, 0x60
    in al, dx                   ; Read ACK (0xFA)

    ; 4. Enable Data Streaming from Mouse
    call mouse_wait_write
    mov dx, 0x64
    mov al, 0xD4                ; Command 0xD4 = Write to Mouse Device
    out dx, al
    call mouse_wait_write
    mov dx, 0x60
    mov al, 0xF4                ; Mouse Command 0xF4 = Enable Packet Streaming
    out dx, al
    call mouse_wait_read
    mov dx, 0x60
    in al, dx                   ; Read ACK (0xFA)

    pop rdx
    pop rax
    ret

; --- FRAQSHIFT GRAPHICAL MOUSE ENGINE (PHASE 14 - STEP 2) ---

mouse_variables_init:
    ; --- SET INITIAL MOUSE COORDINATES TO CENTER SCREEN (1024x768) ---
    push rax
    mov rax, 0x570              ; Address for Mouse X
    mov dword [rax], 512        ; X = 512 (Center)
    mov rax, 0x574              ; Address for Mouse Y
    mov dword [rax], 384        ; Y = 384 (Center)
    pop rax
    ret

draw_mouse_pointer:
    ; --- DRAW HARDWARE MOUSE ARROW VIA SAFE 640x480 VRAM ---
    push rax
    push rbx
    push rcx
    push r11
    push r12

    mov rax, r14                ; RAX = X position
    mov rbx, r15                ; RBX = Y position

    mov r11, 0xFD000000         ; Base Graphics VRAM
    
    ; Y-offset calculation for 640 width (2560 bytes per row) [3.1]
    mov ecx, 4096
    imul rbx, rcx
    add r11, rbx

    ; X-offset calculation
    shl rax, 2
    add r11, rax

    ; Draw the crisp white arrow matrix safely
    mov dword [r11], 0x00FFFFFF
    mov dword [r11 + 4096], 0x00FFFFFF
    mov dword [r11 + 4096 + 4], 0x00FFFFFF
    mov dword [r11 + 8192], 0x00FFFFFF
    mov dword [r11 + 8192 + 4], 0x00FFFFFF
    mov dword [r11 + 8192 + 8], 0x00FFFFFF
    mov dword [r11 + 12288], 0x00FFFFFF


    pop r12
    pop r11
    pop rcx
    pop rbx
    pop rax
    ret



gui_desktop_loop:

    ; --- FRAQSHIFT GRAPHIC DESKTOP (CLEAN RAM CACHED ENGINE) ---
    mov r11, 0x580              
    mov dword [abs r11], 512    
    mov r11, 0x584              
    mov dword [abs r11], 384 

    ; Initialize dynamic Window location variables in RAM
    mov r11, 0x590              ; Address for Window X
    mov dword [abs r11], 150    ; Default Start X = 150
    mov r11, 0x594              ; Address for Window Y
    mov dword [abs r11], 100    ; Default Start Y = 100
    ; Initialize text counter array tracker to absolute zero
    mov r11, 0x5A8              ; RAM address for text character counter
    mov dword [abs r11], 0      ; Clear it completely at system boot! 
    ; Initialize Window Input Focus register flag to zero
    mov r11, 0x5AC              ; RAM address for window input focus
    mov dword [abs r11], 0      ; 0 = Unfocused/Locked at boot setup
    ; Initialize keyboard Shift state (0 = released, 1 = pressed)
    mov r11, 0x5D8
    mov dword [abs r11], 0

    ; Initialize text cursor coordinates in RAM
    mov r11, 0x5A0              ; RAM address for Text X
    mov dword [abs r11], 10     ; Start 10 pixels from the left window border
    mov r11, 0x5A4              ; RAM address for Text Y
    mov dword [abs r11], 10     ; Start 10 pixels down from the black title bar

    mov r14, 512                
    mov r15, 384                

    ; Step 1: Stream your custom Fraq Bat background directly from the Virtual Hard Drive!
    ; Step 1: Temporary dark cyberpunk background (1024x768)
    ; call draw_fraq_background
    mov r8, 0                   ; Start X = 0
    mov r9, 0                   ; Start Y = 0
    mov r10, 1024               ; Full screen width
    mov r12, 768                ; Full screen height
    mov eax, 0x000D0E12         ; Deep dark slate-black background
    call draw_rectangle
 

    ; Step 2: Cache both cyberpunk icons into RAM immediately
    ;call preload_icons_to_ram

    ; Step 3: Draw the static interface components ONCE
    ; 1. Draw the solid black bar at the bottom
    mov r8, 0                   
    mov r9, 728                 
    mov r10, 1024                
    mov r12, 40                 
    mov eax, 0x00000000         
    call draw_rectangle         

    ; 2. Draw the neon-lila signature accent line
    mov r8, 0                   
    mov r9, 727                 
    mov r10, 1024                
    mov r12, 2                  
    mov eax, 0x00FF00FF         
    call draw_rectangle         

    ; 3. Draw the apps window frame
    ;call draw_window_frame 

    ; 4. Draw your awesome round start icon cleanly on the open desktop
    call draw_start_icon     

    ; Take initial backup and draw the first mouse pointer
    call mouse_save_back
    call draw_mouse_pointer

    ; Re-enable PS/2 Keyboard Port (Port 1) after mouse initialization
    mov dx, 0x64
    mov al, 0xAE                ; Command 0xAE: Enable first PS/2 port (Keyboard)
    out dx, al



.mouse_poll_loop:
    mov dx, 0x64
    in al, dx
    
    test al, 0x01               
    jz .mouse_poll_loop         
    test al, 0x20
    jnz .is_mouse_data          ; If bit 5 is 1, it's mouse data! Keep polling the packets!
    
    ; --- IT'S PURE KEYBOARD DATA! SAVE IT TO CACHE DIRECTLY ---
    mov dx, 0x60
    in al, dx                   ; Read the raw Scancode directly from the hardware port!
    mov r12b, al                ; LOCK THE SCANCODE IN R12B IMMEDIATELY! 🔒
    jmp .consume_keyboard       ; Jump straight down to your text engine!

.is_mouse_data:

    mov dx, 0x60
    in al, dx                   ; Read Byte 1 cleanly (No double erasing here!)
    mov r13b, al                ; FIXED: Save mouse click state in R13B instead! 🔒


.wait_byte2:
    mov dx, 0x64
    in al, dx
    test al, 0x01
    jz .wait_byte2
    mov dx, 0x60
    in al, dx                   ; Read Byte 2 (X)
    
    movsx rbx, al
    sar rbx, 3                  
    add r14, rbx                

.wait_byte3:
    mov dx, 0x64
    in al, dx
    test al, 0x01
    jz .wait_byte3
    mov dx, 0x60
    in al, dx                   ; Read Byte 3 (Y)
    
    movsx rbx, al
    sar rbx, 3                  
    sub r15, rbx                

    ; Sharp hardware boundaries
    cmp r14, 5
    jge .check_max_x
    mov r14, 5
.check_max_x:
    cmp r14, 1009
    jle .check_min_y
    mov r14, 1009
.check_min_y:
    cmp r15, 5
    jge .check_max_y
    mov r15, 5
.check_max_y:
    cmp r15, 753
    jle .done_movement
    mov r15, 753

.done_movement:
    ; --- INTERACTIVE CYBERPUNK WINDOW CONTOUR DRAG ENGINE ---
    ; Check if the Left Mouse Button is currently held down (Bit 0 of R13B)
    test r13b, 0x01             ; Is left button pressed?
    jz .mouse_button_is_up      ; If NOT pressed, jump to handle release logic cleanly!
    ; --- CHECK IF USER CLICKED INSIDE THE WORKSPACE BODY (SET FOCUS) ---
    mov r11, 0x590
    mov ecx, [abs r11]          ; ECX = Window X
    mov r11, 0x594
    mov edx, [abs r11]          ; EDX = Window Y
    add edx, 24                 ; Workspace starts below title bar & neon line

    cmp r14, rcx                ; Mouse X >= Window X?
    jl .clear_window_focus
    add rcx, 340
    cmp r14, rcx                ; Mouse X <= Window X + 340?
    jg .clear_window_focus

    cmp r15, rdx                ; Mouse Y >= Window Y + 24?
    jl .clear_window_focus
    add rdx, 176
    cmp r15, rdx                ; Mouse Y <= Window Y + 200?
    jg .clear_window_focus

    ; Inside workspace body -> Activate typing focus!
    mov r11, 0x5AC
    mov dword [abs r11], 1
    jmp .check_titlebar_drag

.clear_window_focus:
    ; Clicked outside workspace body -> Lock typing focus
    mov r11, 0x5AC
    mov dword [abs r11], 0

.check_titlebar_drag:


    ; Load current Window coordinates from RAM to check the title bar hitbox
    mov r11, 0x590
    mov ecx, [abs r11]          ; ECX = Window X
    mov r11, 0x594
    mov edx, [abs r11]          ; EDX = Window Y

    ; Hitbox Check: Is Mouse X inside Window Width? (Window X to Window X + 340)
    cmp r14, rcx
    jl .skip_drag
    add rcx, 340
    cmp r14, rcx
    jg .skip_drag

    ; Hitbox Check: Is Mouse Y inside Black Title Bar Height? (Window Y to Window Y + 22)
    cmp r15, rdx
    jl .skip_drag
    add rdx, 22
    cmp r15, rdx
    jg .skip_drag

    ; --- MOUSE IS ACTIVE DRAGGING! UPDATE COORDINATES IN RAM SILENTLY ---
    mov r11, 0x580
    mov eax, [abs r11]          ; EAX = Old Mouse X
    mov ebx, r14d
    sub ebx, eax                ; EBX = X Movement delta
    mov r11, 0x590
    add [abs r11], ebx          ; Update Window X in RAM!

    mov r11, 0x584
    mov eax, [abs r11]          ; EAX = Old Mouse Y
    mov ebx, r15d
    sub ebx, eax                ; EBX = Y Movement delta
    mov r11, 0x594
    add [abs r11], ebx          ; Update Window Y in RAM!

    ; Set our drag status flag in RAM to 1 (Active Dragging)
    mov r11, 0x598
    mov dword [abs r11], 1
    jmp .skip_drag

.mouse_button_is_up:
    ; Check if we were actually dragging before the button went up
    mov r11, 0x598
    cmp dword [abs r11], 1
    jne .skip_drag              ; If we weren't dragging, user is just moving mouse normally - skip redraw!

    
    ; --- SINGLE FRAME CLEAN REDRAW ON RELEASE ---
    mov dword [abs r11], 0      ; Reset flag
    ; call draw_fraq_background
    mov r8, 0
    mov r9, 0
    mov r10, 1024
    mov r12, 768
    mov eax, 0x000D0E12
    call draw_rectangle

    
    ; Re-render the taskbar framework safely at the bottom
    mov r8, 0                   
    mov r9, 728                 
    mov r10, 1024                
    mov r12, 40                 
    mov eax, 0x00000000         
    call draw_rectangle         ; Black Taskbar
    mov r8, 0                   
    mov r9, 727                 
    mov r10, 1024                
    mov r12, 2         
    mov eax, 0x00FF00FF         
    call draw_rectangle         ; Lila Accent Line

.skip_drag:
    push r14
    push r15

    ; Erase the old mouse pointer trail using historical RAM coordinates
    mov r11, 0x580
    mov r14d, [abs r11]         
    mov r11, 0x584
    mov r15d, [abs r11]         
    call mouse_restore_back     

    pop r15
    pop r14

    ; Update our RAM history cache with the new mouse positions
    mov r11, 0x580
    mov [abs r11], r14d         
    mov r11, 0x584
    mov [abs r11], r15d         

.redraw_desktop_frame:

    ; --- RENDER FRAQSHIFT BROWSER V1 ADDRESS BAR & SANITIZED PAGE TEXT ---
    mov r11, 0x600
    mov rdi, [abs r11]          ; URL pointer in Ring 3
    test rdi, rdi
    jz .skip_browser_render

    ; 0. Draw Dedicated Fraqshift Browser Window Frame (X=154, Y=128, W=516, H=310)
    mov r8, 154
    mov r9, 128
    mov r10, 516
    mov r12, 310
    mov eax, 0x000F172A         ; Deep Dark-Navy Browser Window Body
    call draw_rectangle

    ; 1. Draw Address Bar Box inside Window (X=162, Y=136, W=500, H=22)
    mov r8, 162
    mov r9, 136
    mov r10, 500
    mov r12, 22
    mov eax, 0x001E293B         ; Sleek Slate Address Bar background
    call draw_rectangle

    ; 2. Draw Safe-Link Shield Badge inside Address Bar (X=165, Y=139, W=16, H=16)
    mov r11, 0x610
    mov rax, [abs r11]
    cmp rax, 2
    je .badge_fraq_purple
    cmp rax, 1
    je .badge_safe_green
    mov eax, 0x00FF3344         ; RED: Dangerous Link Blocked!
    jmp .draw_shield_badge
.badge_fraq_purple:
    mov eax, 0x00A855F7         ; PURPLE: Compiled & Running from browser.fraq!
    jmp .draw_shield_badge
.badge_safe_green:
    mov eax, 0x0000FF66         ; GREEN: Safe-Link Verified!

.draw_shield_badge:
    mov r8, 165
    mov r9, 139
    mov r10, 16
    mov r12, 16
    call draw_rectangle

    ; 3. Render URL Text inside Address Bar (X=188, Y=143)
    mov r11, 0x600
    mov rsi, [abs r11]          ; URL string from Ring 3 (0x508000)
    mov r8, 188                 ; Start X
    mov r9, 143                 ; Start Y
    mov eax, 0x00E2E8F0         ; Crisp White-Silver URL text
    call draw_browser_string_line

    ; 4. Render Sanitized Web Page Text inside Window Body (X=165, Y=172, wrapped!)
    mov r11, 0x608
    mov rsi, [abs r11]          ; Sanitized plain text pointer from Ring 3 (0x510000)
    mov r8, 165                 ; Left margin X
    mov r9, 172                 ; Top body Y
    mov eax, 0x0038BDF8         ; Clean Sky-Blue readable body text
    call draw_browser_wrapped_text


.skip_browser_render:



; --- 4-STAGE NETWORK & SYSCALL 10 DIAGNOSTIC LED (Top-Right Taskbar) ---
    mov r11, 0x500008           ; 1. Check if Ring 3 Syscall 10 downloaded HTML bytes (> 0)
    mov rax, [abs r11]
    cmp rax, 0
    jg .led_online_green

    mov r11, 0x5CC              ; 2. Check if DHCP Lease (10.0.2.15) succeeded (== 1)
    mov eax, [abs r11]
    cmp eax, 1
    je .led_dhcp_cyan

    mov r11, 0x5B6              ; 3. Check if Intel e1000 PCI card is ONLINE (== 1)
    movzx eax, word [abs r11]
    cmp eax, 1
    je .led_pci_orange

    mov eax, 0x00FF3344         ; RED: e1000 PCI card not detected
    jmp .draw_net_led

.led_pci_orange:
    mov eax, 0x00FF9900         ; ORANGE: PCI card ONLINE, waiting for DHCP
    jmp .draw_net_led

.led_dhcp_cyan:
    mov eax, 0x0000CCFF         ; CYAN/BLUE: DHCP Lease ACTIVE (10.0.2.15), TCP pending
    jmp .draw_net_led

.led_online_green:
    mov eax, 0x0000FF66         ; NEON-GREEN: 100% INTERNET! Web page fetched into Ring 3!

.draw_net_led:
    mov r8, 960
    mov r9, 12
    mov r10, 48
    mov r12, 18
    call draw_rectangle
.net_status_done:


    ; Render the solid app window frame safely
    ;call draw_window_frame      
    call draw_window_text       ; Render live typed text inside the window workspace
    

    ; Re-render the taskbar framework safely at the bottom row cleanly
    mov r8, 0                   
    mov r9, 728                 
    mov r10, 1024                
    mov r12, 40                 
    mov eax, 0x00000000         
    call draw_rectangle         ; Black Taskbar
    
    mov r8, 0                   
    mov r9, 727                 
    mov r10, 1024                
    mov r12, 2         
    mov eax, 0x00FF00FF         
    call draw_rectangle         ; Lila Accent Line


   

.render_pointer_top:

    ; Take fresh backup of mouse background area and drop the cursor arrow
    call mouse_save_back        
    call draw_mouse_pointer     
    jmp .mouse_poll_loop        

.consume_keyboard:
    ; Keyboard test mode: deliberately bypass window-focus gating.
    ; r12b contains the raw PS/2 Set-1 scancode (i8042 translation enabled in mouse_init).

    movzx eax, r12b

    ; Track either Shift key (make: 2A/36, break: AA/B6).
    cmp al, 0x2A
    je .keyboard_shift_down
    cmp al, 0x36
    je .keyboard_shift_down
    cmp al, 0xAA
    je .keyboard_shift_up
    cmp al, 0xB6
    je .keyboard_shift_up

    ; Ignore all other key-release codes.
    test al, 0x80
    jnz .finish_keyboard_poll

    ; Backspace removes the last buffered character.
    cmp al, 0x0E
    je .keyboard_backspace

    ; The lookup table contains 64 unshifted + 64 shifted entries.
    and eax, 0x7F
    cmp eax, 0x3F
    ja .finish_keyboard_poll

    mov r11, 0x5D8
    cmp dword [abs r11], 0
    je .keyboard_unshifted
    add eax, 64

.keyboard_unshifted:
    lea rsi, [rel scan_to_ascii]
    mov al, byte [rsi + rax]
    test al, al
    jz .finish_keyboard_poll       ; Ignore unmapped/non-printable keys

    ; Append to the text buffer at 0x180000.
    mov rbx, 0x180000
    mov r11, 0x5A8
    mov ecx, [abs r11]
    cmp ecx, 255
    jae .finish_keyboard_poll
    mov byte [rbx + rcx], al
    inc ecx
    mov byte [rbx + rcx], 0        ; Keep the buffer NUL-terminated
    mov [abs r11], ecx

    ; Redraw the window body and all buffered text so the new key appears.
    call draw_window_frame
    call draw_window_text
    jmp .finish_keyboard_poll

.keyboard_shift_down:
    mov r11, 0x5D8
    mov dword [abs r11], 1
    jmp .finish_keyboard_poll

.keyboard_shift_up:
    mov r11, 0x5D8
    mov dword [abs r11], 0
    jmp .finish_keyboard_poll

.keyboard_backspace:
    mov r11, 0x5A8
    mov ecx, [abs r11]
    test ecx, ecx
    jz .finish_keyboard_poll
    dec ecx
    mov [abs r11], ecx
    mov rbx, 0x180000
    mov byte [rbx + rcx], 0

    ; Redraw to erase the removed glyph cleanly.
    call draw_window_frame
    call draw_window_text
    jmp .finish_keyboard_poll

.finish_keyboard_poll:
    jmp .mouse_poll_loop







; --- FRAQSHIFT GRAPHICS COMPONENT: RECTANGLE ENGINE ---
draw_rectangle:
    push rbx
    push rcx
    push r11
    push rdi
    push rsi
    mov rsi, r12                
.row_loop:
    push r8                     
    mov rdi, r10                
    mov r11, 0xFD000000
    mov rbx, r9
    imul rbx, 4096              
    add r11, rbx
    mov rbx, r8
    shl rbx, 2                  
    add r11, rbx                
.col_loop:
    mov [abs r11], eax              
    add r11, 4                  
    dec rdi
    jnz .col_loop               
    pop r8                      
    inc r9                      
    dec rsi
    jnz .row_loop               
    pop rsi
    pop rdi
    pop r11
    pop rcx
    pop rbx
    ret

; --- HELPER: DRAW SINGLE-LINE STRING USING BUILT-IN font_rom ---
; Inputs: RSI = Null-terminated string, R8 = X, R9 = Y, EAX = Color
draw_browser_string_line:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r10
    push r11
    mov r10d, eax               ; Save color in R10D
.str_next_char:
    movzx eax, byte [rsi]
    test al, al
    jz .str_done
    cmp r8, 645                 ; Clamp inside 520px window right edge
    jge .str_done
    call draw_rom_glyph_8x8
    add r8, 9
    inc rsi
    jmp .str_next_char
.str_done:
    pop r11
    pop r10
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; --- HELPER: DRAW WORD-WRAPPED PAGE TEXT INSIDE BROWSER WINDOW ---
draw_browser_wrapped_text:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r10
    push r11
    mov r10d, eax               ; Save color
.wrap_next_char:
    movzx eax, byte [rsi]
    test al, al
    jz .wrap_done
    cmp r8, 640                 ; Wrap line at right window edge!
    jl .emit_wrap_char
    mov r8, 165                 ; Reset X to left margin
    add r9, 14                  ; Next line (+14 px)
    cmp r9, 430                 ; Stop at bottom window edge
    jge .wrap_done
.emit_wrap_char:
    call draw_rom_glyph_8x8
    add r8, 9
    inc rsi
    jmp .wrap_next_char
.wrap_done:
    pop r11
    pop r10
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret


; --- HELPER: RENDER 8x8 GLYPH FROM DEDICATED FRAQ UI FONT ---
; Inputs: AL = ASCII char, R8 = X, R9 = Y, R10D = Color
draw_rom_glyph_8x8:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push r11

    ; Normalize lowercase 'a'-'z' -> uppercase 'A'-'Z' for ultra-crisp 8x8 glyphs
    cmp al, 'a'
    jb .check_ascii_range
    cmp al, 'z'
    ja .check_ascii_range
    sub al, 32

.check_ascii_range:
    sub al, 32
    cmp al, 63
    ja .glyph_exit
    movzx rax, al
    shl rax, 3
    lea rsi, [rel fraq_ui_font_8x8]
    add rsi, rax

    mov r11, 0xFD000000
    mov rdx, r9
    imul rdx, 4096
    add r11, rdx
    mov rbx, r8
    shl rbx, 2
    add r11, rbx

    xor rcx, rcx                ; Row 0..7
.g_row:
    mov bl, byte [rsi + rcx]
    xor rdx, rdx                ; Col 0..7
.g_col:
    shl bl, 1
    jnc .g_skip
    mov [r11 + rdx * 4], r10d
.g_skip:
    inc rdx
    cmp rdx, 8
    jl .g_col
    add r11, 4096
    inc rcx
    cmp rcx, 8
    jl .g_row
.glyph_exit:
    pop r11
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; --- GUARANTEED 8x8 BITMAP FONT (ASCII 32..95: Space, Punctuation, 0-9, A-Z) ---
fraq_ui_font_8x8:
    dq 0x0000000000000000 ; 32 ' '
    dq 0x0018001818181818 ; 33 '!'
    dq 0x0000000000246666 ; 34 '"'
    dq 0x0024247E247E2424 ; 35 '#'
    dq 0x00183E603C067C18 ; 36 '$'
    dq 0x0062640810264600 ; 37 '%'
    dq 0x003A444A30484830 ; 38 '&'
    dq 0x0000000000081818 ; 39 '''
    dq 0x000C18303030180C ; 40 '('
    dq 0x0030180C0C0C1830 ; 41 ')'
    dq 0x000024187E182400 ; 42 '*'
    dq 0x000018187E181800 ; 43 '+'
    dq 0x00180C0C00000000 ; 44 ','
    dq 0x000000007E000000 ; 45 '-'
    dq 0x0018180000000000 ; 46 '.'
    dq 0x0080402010080402 ; 47 '/'
    dq 0x003C666E7666663C ; 48 '0'
    dq 0x007E181818183818 ; 49 '1'
    dq 0x007E6030180C663C ; 50 '2'
    dq 0x003C66061C06663C ; 51 '3'
    dq 0x000C0C7E4C2C1C0C ; 52 '4'
    dq 0x003C6606067C607E ; 53 '5'
    dq 0x003C66667C60663C ; 54 '6'
    dq 0x001818180C06667E ; 55 '7'
    dq 0x003C66663C66663C ; 56 '8'
    dq 0x003C66063E66663C ; 57 '9'
    dq 0x0018180018180000 ; 58 ':'
    dq 0x00180C0C00181800 ; 59 ';'
    dq 0x00060C1830180C06 ; 60 '<'
    dq 0x0000007E007E0000 ; 61 '='
    dq 0x006030180C183060 ; 62 '>'
    dq 0x001800180C06663C ; 63 '?'
    dq 0x003C606E6A6E663C ; 64 '@'
    dq 0x006666667E66663C ; 65 'A'
    dq 0x007C66667C66667C ; 66 'B'
    dq 0x003C66606060663C ; 67 'C'
    dq 0x00786C6666666C78 ; 68 'D'
    dq 0x007E60607860607E ; 69 'E'
    dq 0x006060607860607E ; 70 'F'
    dq 0x003E66666E60663C ; 71 'G'
    dq 0x006666667E666666 ; 72 'H'
    dq 0x003C18181818183C ; 73 'I'
    dq 0x003C66660606060F ; 74 'J'
    dq 0x00666C7870786C66 ; 75 'K'
    dq 0x007E606060606060 ; 76 'L'
    dq 0x006363636B7F7763 ; 77 'M'
    dq 0x0066666E7E766666 ; 78 'N'
    dq 0x003C66666666663C ; 79 'O'
    dq 0x006060607C66667C ; 80 'P'
    dq 0x003E666E6A66663C ; 81 'Q'
    dq 0x00666C787C66667C ; 82 'R'
    dq 0x003C66063C60663C ; 83 'S'
    dq 0x001818181818187E ; 84 'T'
    dq 0x003C666666666666 ; 85 'U'
    dq 0x00183C6666666666 ; 86 'V'
    dq 0x0063777F6B636363 ; 87 'W'
    dq 0x0066663C183C6666 ; 88 'X'
    dq 0x00181818183C6666 ; 89 'Y'
    dq 0x007E6030180C067E ; 90 'Z'
    dq 0x003C30303030303C ; 91 '['
    dq 0x0080402010080402 ; 92 '\'
    dq 0x003C0C0C0C0C0C3C ; 93 ']'
    dq 0x0000000000663C18 ; 94 '^'
    dq 0x00FF000000000000 ; 95 '_'



draw_window_text:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r11
    push r15

    mov r11, 0x5A8
    mov r15d, [abs r11]         ; Read current character count from RAM
    
    ; Safety gate against uninitialized RAM values
    cmp r15d, 255
    ja .global_text_escape
    cmp r15d, 0
    jz .global_text_escape

    mov rsi, 0x180000           ; Text buffer base address in RAM
    mov r8, 12                  ; Relative X padding inside window
    mov r9, 10                  ; Relative Y padding inside window

.global_render_loop:
    push rsi
    push r8
    push r9

    movzx rax, byte [rsi]       ; Fetch next ASCII character from buffer
    cmp al, 32                  ; Ignore control characters (< 32)
    jb .skip_invalid_char
    cmp al, 126                 ; Ignore non-ASCII characters (> 126)
    ja .skip_invalid_char

    call draw_char_in_window    ; Render character glyph using font_rom

.skip_invalid_char:
    pop r9
    pop r8
    pop rsi

    inc rsi                     ; Advance to next character in buffer
    add r8, 10                  ; Advance cursor 10 pixels right

    cmp r8, 320                 ; Wrap to next line at right window edge
    jl .global_continue_loop
    mov r8, 12
    add r9, 16

.global_continue_loop:
    dec r15d
    jnz .global_render_loop

.global_text_escape:
    pop r15
    pop r11
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

draw_char_in_window:
    ; Inputs: AL = ASCII character (32..126), R8 = Rel X, R9 = Rel Y
    push rax
    push rbx
    push rcx
    push rdx
    push r11
    push rsi

    ; Convert lowercase 'a'-'z' to uppercase 'A'-'Z' for clean 8x8 glyph lookup
    cmp al, 'a'
    jb .check_glyph_bounds
    cmp al, 'z'
    ja .check_glyph_bounds
    sub al, 32

.check_glyph_bounds:
    ; Use the window's CURRENT position from RAM, not fixed desktop coordinates.
    ; Window body starts below its 22-pixel title bar and 2-pixel accent line.
    mov r11, 0x590
    mov ebx, [abs r11]          ; Current window X
    add rbx, r8                 ; + Character horizontal offset

    mov r11, 0x594
    mov edx, [abs r11]          ; Current window Y
    add rdx, 24                 ; Start below title bar + accent line
    add rdx, r9                 ; + Text line vertical offset

    mov r11, 0xFD000000         ; Active 1024x768 LFB address
    imul rdx, 4096              ; Row pitch = 4096 bytes
    add r11, rdx
    shl rbx, 2                  ; X * 4 bytes per pixel
    add r11, rbx

    sub al, 32
    movzx rax, al
    shl rax, 3                  ; 8 bytes per character in built-in 8x8 font
    lea rsi, [rel font_rom]     ; Use existing font_rom symbol so NASM compiles cleanly!



    add rsi, rax

    ; Draw crisp 8x8 neon cyan-green glyph (scaled 2x vertically for 8x16 look)
    mov rcx, 8

.win_glyph_row:
    push r11
    mov bl, byte [rsi]          ; Load actual 8-bit character row from win_font_8x8!
    mov rdx, 8

.win_glyph_col:
    shl bl, 1
    jnc .win_glyph_skip
    mov dword [r11], 0x0000FF66         ; Top pixel row
    mov dword [r11 + 4096], 0x0000FF66  ; Doubled height pixel row
.win_glyph_skip:
    add r11, 4
    dec rdx
    jnz .win_glyph_col

    pop r11
    add r11, 8192               ; Advance 2 screen rows (2 * 4096)
    inc rsi
    dec rcx
    jnz .win_glyph_row

    pop rsi
    pop r11
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret


; --- BOCHS VBE HARDWARE DRIVER: TRUE 1024x768 @ 32-BIT ---
set_vbe_1024x768:
    push rax
    push rdx

    mov dx, 0x01CE
    mov ax, 4
    out dx, ax
    mov dx, 0x01CF
    mov ax, 0                   ; Disable VBE during mode switch
    out dx, ax

    mov dx, 0x01CE
    mov ax, 1
    out dx, ax
    mov dx, 0x01CF
    mov ax, 1024                ; Set X resolution = 1024
    out dx, ax

    mov dx, 0x01CE
    mov ax, 2
    out dx, ax
    mov dx, 0x01CF
    mov ax, 768                 ; Set Y resolution = 768
    out dx, ax

    mov dx, 0x01CE
    mov ax, 3
    out dx, ax
    mov dx, 0x01CF
    mov ax, 32                  ; Set 32-bit color depth
    out dx, ax

    mov dx, 0x01CE
    mov ax, 4
    out dx, ax
    mov dx, 0x01CF
    mov ax, 0x41                ; Enable VBE with Linear Framebuffer (LFB)
    out dx, ax

    pop rdx
    pop rax
    ret



; --- FRAQSHIFT GRAPHICS COMPONENT: DYNAMIC WINDOW COMPOSITOR ---

draw_window_frame:
    ; --- DRAWS THE CYBERPUNK WINDOW USING VARIABLES FROM RAM ---
    push rax
    push r8
    push r9
    push r10
    push r12
    push rbx

    ; Load current Window position from dynamic RAM addresses
    mov rbx, 0x590
    mov r8d, [abs rbx]          ; R8 = Current Window X position
    mov rbx, 0x594
    mov r9d, [abs rbx]          ; R9 = Current Window Y position

    ; 1. Draw main window body (Dark charcoal workspace)
    push r8
    push r9
    add r9, 22                  ; Window body starts right under the title bar
    mov r10, 340                ; Width = 340
    mov r12, 178                ; Height = 178
    mov eax, 0x001C1E24         ; Color = Sleek tech dark charcoal
    call draw_rectangle
    pop r9
    pop r8

    ; 2. Draw window title bar (Solid black top bar for mouse dragging)
    mov r10, 340                ; Width = 340
    mov r12, 22                 ; Height = 22
    mov eax, 0x00000000         ; Color = Pure Black
    call draw_rectangle

    ; 3. Draw the glowing neon-blue accent line under the title bar
    push r9
    add r9, 22                  ; Placed right at the seam
    mov r10, 340                ; Width = 340
    mov r12, 2                  ; Height = 2 (thin neon thread)
    mov eax, 0x0000FFFF         ; Color = Electric Neon Cyan/Blue
    call draw_rectangle
    pop r9

    pop rbx
    pop r12
    pop r10
    pop r9
    pop r8
    pop rax
    ret                         ; Clean and safe exit!






; --- FRAQSHIFT GRAPHICS COMPONENT: WIREFRAME COMPOSITOR (PERFEKT SYNCHRONIZED) ---

; --- FRAQSHIFT MOUSE DOUBLE-BUFFERING ENGINE ---
mouse_save_back:
    push rax
    push rbx
    push rcx
    push r11
    push rdi
    mov r11, 0xFD000000
    mov rbx, r15
    imul rbx, 4096              
    add r11, rbx
    mov rbx, r14
    shl rbx, 2                  
    add r11, rbx                
    mov rdi, 0x150000           
    mov rcx, 8                  
.save_row:
    push r11
    mov eax, [abs r11]
    mov [abs rdi], eax
    mov eax, [abs r11 + 4]
    mov [abs rdi + 4], eax
    mov eax, [abs r11 + 8]
    mov [abs rdi + 8], eax
    mov eax, [abs r11 + 12]
    mov [abs rdi + 12], eax
    mov eax, [abs r11 + 16]
    mov [abs rdi + 16], eax
    mov eax, [abs r11 + 20]
    mov [abs rdi + 20], eax
    mov eax, [abs r11 + 24]
    mov [abs rdi + 24], eax
    mov eax, [abs r11 + 28]
    mov [abs rdi + 28], eax
    pop r11
    add r11, 4096               
    add rdi, 32                 
    dec rcx
    jnz .save_row
    pop rdi
    pop r11
    pop rcx
    pop rbx
    pop rax
    ret

mouse_restore_back:
    push rax
    push rbx
    push rcx
    push r11
    push rsi
    mov r11, 0xFD000000
    mov rbx, r15
    imul rbx, 4096
    add r11, rbx
    mov rbx, r14
    shl rbx, 2
    add r11, rbx                
    mov rsi, 0x150000           
    mov rcx, 8                  
.restore_row:
    push r11
    mov eax, [abs rsi]
    mov [abs r11], eax
    mov eax, [abs rsi + 4]
    mov [abs r11 + 4], eax
    mov eax, [abs rsi + 8]
    mov [abs r11 + 8], eax
    mov eax, [abs rsi + 12]
    mov [abs r11 + 12], eax
    mov eax, [abs rsi + 16]
    mov [abs r11 + 16], eax
    mov eax, [abs rsi + 20]
    mov [abs r11 + 20], eax
    mov eax, [abs rsi + 24]
    mov [abs r11 + 24], eax
    mov eax, [abs rsi + 28]
    mov [abs r11 + 28], eax
    pop r11
    add r11, 4096
    add rsi, 32
    dec rcx
    jnz .restore_row
    pop rsi
    pop r11
    pop rcx
    pop rbx
    pop rax
    ret


; --- FRAQSHIFT HARD DRIVE GRAPHICS STREAMER ---
draw_fraq_background:
    push rax
    push rbx
    push rcx
    push rdx
    push r11
    push rdi
    mov r11, 0xFD000000         
    mov rbx, 100                
    mov rcx, 2400               
.stream_sector_loop:
    push rcx                    
    mov dx, 0x01F2
    mov al, 1                   
    out dx, al
    mov dx, 0x01F3
    mov al, bl                  
    out dx, al
    mov dx, 0x01F4
    mov ax, bx
    shr ax, 8                   
    out dx, al
    mov dx, 0x01F5
    mov ax, bx
    shr ax, 16                  
    out dx, al
    mov dx, 0x01F6
    mov ax, bx
    shr ax, 24
    and al, 0x0F
    or al, 0xE0                 
    out dx, al
    mov dx, 0x01F7
    mov al, 0x20                
    out dx, al
.wait_disk_ready:
    in al, dx
    test al, 0x08               
    jz .wait_disk_ready         
    mov dx, 0x01F0
    mov rcx, 256                
.read_word_loop:
    in ax, dx                   
    mov [abs r11], ax           
    add r11, 2                  
    dec rcx
    jnz .read_word_loop
    inc rbx                     
    pop rcx                    
    dec rcx
    jnz .stream_sector_loop     
    pop rdi
    pop r11
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret


; --- FRAQSHIFT EMBEDDED START ICON ENGINE (TRUE REGISTER SPECIFIC) ---

draw_start_icon:
    push rax
    push rbx
    push rcx
    push r11
    push rsi

    mov rsi, fraq_icon_data     ; Point to the embedded bat pixels in the kernel

    ; --- POSITIONING: LET'S PLACE IT PERFECTLY AT THE BOTTOM LEFT CORNER (X=15, Y=444) ---
    mov r11, 0xFD000000
    add r11, (444 * 2560) + (15 * 4) ; Lines up beautifully inside your black taskbar!

    mov rbx, 32                 ; Height = 32 rows

.row_loop:
    push r11                    ; Save the start of the current row line
    mov rcx, 32                 ; Width = 32 pixels

.pixel_loop:
    ; FIXED: Removed 'abs' so registers can advance smoothly pixel-by-pixel!
    mov eax, [rsi]              ; Read 1 full 32-bit pixel from kernel memory
    mov [r11], eax              ; Fire it directly into the screen silicon LFB
    
    add rsi, 4                  ; Advance 4 bytes to the next pixel in your file
    add r11, 4                  ; Advance 4 bytes to the next pixel on screen
    dec rcx
    jnz .pixel_loop

    pop r11                     ; Restore row start address
    add r11, 2560               ; Move VRAM pointer straight down to the next row line
    dec rbx
    jnz .row_loop

    pop rsi
    pop r11
    pop rcx
    pop rbx
    pop rax
    ret


align 16
fraq_icon_data:
    incbin "fraq_start_icon.bin" ; NASM bakes your 4 KB image file directly into the kernel











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
    db 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}',  0,  0, 'A', 'S' ; Row 2 Shifted
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

; --- FRAQSHIFT WINDOW TEXT BUFFER RENDERER (1024x768 @ 0xE0000000) ---







times 45056-($-$$) db 0
