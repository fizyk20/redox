SECTION .text
USE16
; Generate a memory map at 0x500 to 0x5000 (available memory not used for kernel or bootloader)
memory_map:
.start  equ 0x0500
.end    equ 0x5000
.length equ .end - .start

    xor eax, eax
; initialize di to the start of the buffer
    mov di, .start
    mov ecx, .length / 4 ; moving 4 Bytes at once
    cld
    rep stosd

    mov di, .start
    mov edx, 0x534D4150
    xor ebx, ebx
.lp:
	; call Query System Address Map function
	; eax = 0E820h - the code identifying the function
	; ebx = "continuation value"
	; ecx = buffer size in bytes
	; edx = 'SMAP' (a signature for verification)
	; es:di = buffer pointer
	mov eax, 0xE820	
	mov ecx, 24
	int 0x15	; call function
	jc .done 	; Error or finished

	; if returned "continuation value" is 0, stop
	cmp ebx, 0
	je .done

	; increase di to point to the next entry in the buffer
	add di, 24
	cmp di, .end
	jb .lp ; Still have buffer space
.done:
    ret
