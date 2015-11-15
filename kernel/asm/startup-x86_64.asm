startup:
  ; Enable A20 line, which allows usage of memory above 1MB mark
  in al, 0x92
  or al, 2
  out 0x92, al

  ; generate memory map info at address 0x0500
  call memory_map

  ; initialize VESA graphics
  call vesa

  ; set up: 
  ; - FPU (Floating-Point Unit)
  ; - SSE (Streaming SIMD Extensions)
  ; - PIT (Programmable Interval Timer)
  ; - PIC (Programmable Interrupt Controller)
  call initialize.fpu
  call initialize.sse
  call initialize.pit
  call initialize.pic

  cli

  ; initialize es:edi to 8000h:00000000 (= physical address 80000h)
  mov ax, 0x8000
  mov es, ax
  xor edi, edi

  ; zero 12 kB at es:edi for page descriptors
  ; these contain of:
  ; - 512 8-byte entries for Page Map Level 4 (at 80000h)
  ; - 512 8-byte entries for Page Directory Pointer table (at 81000h)
  ; - 512 8-byte entries for Page Directory table (at 82000h)
  xor eax, eax
  mov ecx, 3 * 1024 ; PML4, PDP, PD
  rep stosd

  xor edi, edi
  ; Link first PML4 to PDP
  mov DWORD [es:edi], 0x81000 | 1 << 1 | 1  ; present, writable
  add edi, 0x1000
  ; Link first PDP to PD
  mov DWORD [es:edi], 0x82000 | 1 << 1 | 1  ; present, writable
  add edi, 0x1000
  ; edi now points to PD
  ; Link first PD to 1 GiB of memory
  mov ebx, 1 << 7 | 1 << 1 | 1  ; ebx will be used to fill entries - initialize with present/writable/huge page (= 2MiB)
  ; prepare for looping through 512 entries
  mov ecx, 512
.setpd:
  ; fill each entry in PD with 2 MB pages
  mov [es:edi], ebx ; fill the entry
  add ebx, 0x200000 ; the address of the next page should be 2 MiB further (2MiB = 200000h)
  add edi, 8        ; point to the next entry
  loop .setpd
  ; now the page table is set to address the first 1 GiB of memory

  ; zero es again
  xor ax, ax
  mov es, ax

  ; initialize cr3 to the address of PML4
  mov edi, 0x80000
  mov cr3, edi

  ;  enable PAE and PSE in cr4 (Physical Address Extension, Page Size Extension)
  mov eax, cr4
  or eax, 1 << 5 | 1 << 4
  mov cr4, eax

  ; load protected mode GDT and IDT
  lgdt [gdtr]
  lidt [idtr]

  mov ecx, 0xC0000080               ; Read from the EFER (Extended Feature Enable Register) MSR.
  rdmsr
  or eax, 0x00000100                ; Set the LME bit (Long Mode Enable).
  wrmsr

  mov ebx, cr0                      ; Activate long mode -
  or ebx, 0x80000001                ; - by enabling paging and protection simultaneously.
  mov cr0, ebx

  ; far jump to load CS with 64 bit segment
  jmp 0x08:long_mode

%include "asm/memory_map.asm"
%include "asm/vesa.asm"
%include "asm/initialize.asm"

long_mode:
    use64
    ; load all the other segments with 64 bit data segments
    mov rax, 0x10
    mov ds, rax
    mov es, rax
    mov fs, rax
    mov gs, rax
    mov ss, rax
    ; set up stack
    mov rsp, 0x200000 - 128

    ; load task register
    mov rax, gdt.tss
    ltr ax

    ; rust init
    ; load the kernel entry point as interrupt handling procedure
    xor rax, rax
    mov eax, [kernel_file + 0x18]
    mov [interrupts.handler], rax

    ; copy (kernel_file.font-kernel_file) bytes from kernel_file+0xB000 to kernel_file
    ; code in 64-bit kernel ELF is shifted by B000 bytes, so we need to shift it back
    mov rdi, kernel_file
    mov rsi, rdi
    add rsi, 0xB000
    mov rcx, (kernel_file.font - kernel_file)
    cld
    rep movsb

    ; cleanup of the leftovers after code shifting
    ; zero 0xB000 bytes of memory until kernel_file.font
    mov rdi, kernel_file.font
    mov rcx, 0xB000
    xor rax, rax
    std
    rep stosb

    cld

    ; load parameters into rax and rbx
    mov rax, kernel_file.font
    mov rbx, tss
    ; trigger interrupt 255, which will execute the kernel initialization function
    int 255

; if something went wrong, halt the CPU / loop
.lp:
    sti
    hlt
    jmp .lp

gdtr:
    dw gdt.end + 1  ; size
    dq gdt          ; offset

gdt:
.null equ $ - gdt
    dq 0

.kernel_code equ $ - gdt
    dw 0xffff       ; limit 0:15
    dw 0            ; base 0:15
    db 0            ; base 16:23
    db 0b10011010   ; access byte - code
    db 0b10101111   ; flags (limit in pages + 64-bit flag)/(limit 16:19)
    db 0            ; base 24:31

.kernel_data equ $ - gdt
    dw 0xffff       ; limit 0:15
    dw 0            ; base 0:15
    db 0            ; base 16:23
    db 0b10010010   ; access byte - data
    db 0b10101111   ; flags (limit in pages + 64-bit flag)/(limit 16:19)
    db 0            ; base 24:31

.user_code equ $ - gdt
    dw 0xffff       ; limit 0:15
    dw 0            ; base 0:15
    db 0            ; base 16:23
    db 0b11111010   ; access byte - code
    db 0b10101111   ; flags (limit in pages + 64-bit flag)/(limit 16:19)
    db 0            ; base 24:31

.user_data equ $ - gdt
    dw 0xffff       ; limit 0:15
    dw 0            ; base 0:15
    db 0            ; base 16:23
    db 0b11110010   ; access byte - data
    db 0b10101111   ; flags (limit in pages + 64-bit flag)/(limit 16:19)
    db 0            ; base 24:31

.tss equ $ - gdt
    dw (tss.end-tss) & 0xFFFF                       ; limit 0:15
    dw (tss-$$+0x7C00) & 0xFFFF                     ; base 0:15
    db ((tss-$$+0x7C00) >> 16) & 0xFF               ; base 16:23
    db 0b11101001                                   ; access byte - data
    db 0b01100000 | ((tss.end-tss) >> 16) & 0xF     ; flags/(limit 16:19). flag is set to 32 bit protected mode
    db ((tss-$$+0x7C00) >> 24) & 0xFF               ; base 24:31
    dq 0

.end equ $ - gdt

struc TSS
    .reserved1 resd 1     ;The previous TSS - if we used hardware task switching this would form a linked list.
    .rsp0 resq 1          ;The stack pointer to load when we change to kernel mode.
    .rsp1 resq 1          ;everything below here is unusued now..
    .rsp2 resq 1
    .reserved2 resd 1
    .reserved3 resd 1
    .ist1 resq 1
    .ist2 resq 1
    .ist3 resq 1
    .ist4 resq 1
    .ist5 resq 1
    .ist6 resq 1
    .ist7 resq 1
    .reserved4 resd 1
    .reserved5 resd 1
    .reserved6 resw 1
    .iomap_base resw 1
endstruc

tss:
    istruc TSS
        at TSS.rsp0, dd 0x200000 - 128
        at TSS.iomap_base, dw 0xFFFF
    iend
.end:

%include "asm/interrupts-x86_64.asm"
