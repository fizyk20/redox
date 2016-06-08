%include "asm/startup-common.asm"

startup_arch:
    cli
    ; setting up Page Tables
    ; Identity Mapping first GB
    mov ax, 0x7000
    mov es, ax

    xor edi, edi
    xor eax, eax
    mov ecx, 3 * 4096 / 4 ;PML4, PDP, PD / moves 4 Bytes at once
    cld
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
  mov edi, 0x70000
  mov cr3, edi

    ;enable Page Address Extension and Page Size Extension
    mov eax, cr4
    or eax, 1 << 5 | 1 << 4
    mov cr4, eax

    ; load protected mode GDT
    lgdt [gdtr]

    mov ecx, 0xC0000080               ; Read from the EFER MSR.
    rdmsr
    or eax, 0x00000100                ; Set the Long-Mode-Enable bit.
    wrmsr

    ;enabling paging and protection simultaneously
    mov ebx, cr0
    or ebx, 0x80000001                ;Bit 31: Paging, Bit 0: Protected Mode
    mov cr0, ebx

    ; far jump to enable Long Mode and load CS with 64 bit segment
    jmp gdt.kernel_code:long_mode

USE64
long_mode:
    ; load all the other segments with 64 bit data segments
    mov rax, gdt.kernel_data
    mov ds, rax
    mov es, rax
    mov fs, rax
    mov gs, rax
    mov ss, rax

    ; load long mode IDT
    lidt [idtr]

    mov rsp, 0x800000 - 128

    mov rax, gdt.tss
    ltr ax

    ; rust init
    ; load the kernel entry point as interrupt handling procedure
    mov eax, [kernel_base + 0x18]
    mov [interrupts.handler], rax
    mov rax, tss
    int 0xFF
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
    istruc GDTEntry
        at GDTEntry.limitl, dw 0
        at GDTEntry.basel, dw 0
        at GDTEntry.basem, db 0
        at GDTEntry.attribute, db attrib.present | attrib.user | attrib.code
        at GDTEntry.flags__limith, db flags.long_mode
        at GDTEntry.baseh, db 0
    iend

    .kernel_data equ $ - gdt
    istruc GDTEntry
        at GDTEntry.limitl, dw 0
        at GDTEntry.basel, dw 0
        at GDTEntry.basem, db 0
    ; AMD System Programming Manual states that the writeable bit is ignored in long mode, but ss can not be set to this descriptor without it
        at GDTEntry.attribute, db attrib.present | attrib.user | attrib.writable
        at GDTEntry.flags__limith, db 0
        at GDTEntry.baseh, db 0
    iend

    .user_code equ $ - gdt
    istruc GDTEntry
        at GDTEntry.limitl, dw 0
        at GDTEntry.basel, dw 0
        at GDTEntry.basem, db 0
        at GDTEntry.attribute, db attrib.present | attrib.ring3 | attrib.user | attrib.code
        at GDTEntry.flags__limith, db flags.long_mode
        at GDTEntry.baseh, db 0
    iend

    .user_data equ $ - gdt
    istruc GDTEntry
        at GDTEntry.limitl, dw 0
        at GDTEntry.basel, dw 0
        at GDTEntry.basem, db 0
    ; AMD System Programming Manual states that the writeable bit is ignored in long mode, but ss can not be set to this descriptor without it
        at GDTEntry.attribute, db attrib.present | attrib.ring3 | attrib.user | attrib.writable
        at GDTEntry.flags__limith, db 0
        at GDTEntry.baseh, db 0
    iend

    .tss equ $ - gdt
    istruc GDTEntry
        at GDTEntry.limitl, dw (tss.end - tss) & 0xFFFF
        at GDTEntry.basel, dw (tss-$$+0x7C00) & 0xFFFF
        at GDTEntry.basem, db ((tss-$$+0x7C00) >> 16) & 0xFF
        at GDTEntry.attribute, db attrib.present | attrib.ring3 | attrib.tssAvailabe64
        at GDTEntry.flags__limith, db ((tss.end - tss) >> 16) & 0xF
        at GDTEntry.baseh, db ((tss-$$+0x7C00) >> 24) & 0xFF
    iend
    dq 0 ;tss descriptors are extended to 16 Bytes

    .end equ $ - gdt

    struc TSS
        .reserved1 resd 1    ;The previous TSS - if we used hardware task switching this would form a linked list.
        .rsp0 resq 1        ;The stack pointer to load when we change to kernel mode.
        .rsp1 resq 1        ;everything below here is unused now..
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
            at TSS.rsp0, dd 0x800000 - 128
            at TSS.iomap_base, dw 0xFFFF
        iend
    .end:

    %include "asm/interrupts-x86_64.asm"
