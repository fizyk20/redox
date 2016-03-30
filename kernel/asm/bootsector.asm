; The bootloader

ORG 0x7C00
SECTION .text
USE16

boot: ; dl comes with disk
    ; initialize segment registers
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax

    ; initialize stack
    mov sp, 0x7C00

    mov [disk], dl  ; save the disk code

    ; print "Redox loader"
    mov si, name
    call print
    call print_line

    ; print disk code
    mov bh, 0
    mov bl, [disk]
    call print_num
    call print_line

    mov ax, (fs_header - boot)/512  ; sector number of the filesystem header
    mov bx, fs_header   ; address where filesystem header will be loaded
    mov cx, (startup_end - fs_header)/512   ; size of data to be read in sectors (header + startup + kernel + fonts)
    xor dx, dx  ; set dx to 0
    call load
    ; now the filesystem data and kernel are loaded at 0:[fs_header]

    ; print "Finished"
    mov si, finished
    call print
    call print_line

    jmp startup

; load some sectors from disk to a buffer in memory
; buffer has to be below 1MiB
; IN
;   ax: start sector
;   bx: offset of buffer
;   cx: number of sectors (512 Bytes each)
;   dx: segment of buffer
; CLOBBER
;   ax, bx, cx, dx, si
; TODO rewrite to (eventually) move larger parts at once
; if that is done increase buffer_size_sectors in startup-common to that (max 0x80000 - startup_end)
load:
    cmp cx, 64
    jbe .good_size

    ; if we have more than 64 sectors to read, we read 64 sectors and increase counters
    pusha
    mov cx, 64
    call load
    popa
    add ax, 64  ; add 64 to the number of the sector to be read
    add dx, 64 * 512 / 16  ; increase the segment of the destination (which effectively moves the pointer, offset will be left unchanged)
    sub cx, 64  ; decrease the number of sectors left

    jmp load
.good_size:
    ; initialize the struct describing the data to be read
    mov [DAPACK.addr], ax
    mov [DAPACK.buf], bx
    mov [DAPACK.count], cx
    mov [DAPACK.seg], dx

    ; print "Loading"
    mov si, loading
    call print
    call print_line

    ; print the number of the sector being read
    mov bx, [DAPACK.addr]
    call print_num

    ; print "#"
    mov al, '#'
    call print_char

    ; print the number of sectors to be read
    mov bx, [DAPACK.count]
    call print_num

    call print_line

    ; print segment:offset of the current buffer location
    mov bx, [DAPACK.seg]
    call print_num

    mov al, ':'
    call print_char

    mov bx, [DAPACK.buf]
    call print_num

    call print_line

    ; BIOS Extended Read Sectors
    mov dl, [disk]  ; disk code
    mov si, DAPACK  ; Disk Address Packet
    mov ah, 0x42    ; function 42h = Extended Read
    int 0x13        ; call function
    jc error
    ret

error:
    mov si, errored
    call print
    call print_line
.halt:
    cli
    hlt
    jmp .halt

%include "asm/print16.asm"

name: db "Redox Loader",0
loading: db "Loading",0
errored: db "Could not read disk",0
finished: db "Finished",0
line: db 13,10,0

disk: db 0  ; remembers the code of the disk from which we are booting

; The Disk Address Packet for function 42h/int 13h
DAPACK:
        db 0x10
        db 0
.count: dw 0 ; int 13 resets this to # of blocks actually read/written
.buf:   dw 0 ; offset of the destination address (7E00 = 7C00 (bootloader) + 200 (=512 bytes, the size of the bootloader))
.seg:   dw 0 ; segment of the destination address
.addr:  dd 0 ; the number of the first sector to be read
        dd 0 ; more storage bytes only for big sector numbers ( > 4 bytes )

times 510-($-$$) db 0
db 0x55
db 0xaa
