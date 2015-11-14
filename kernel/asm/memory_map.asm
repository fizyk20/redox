SECTION .text
[BITS 16]
; Generate a memory map at 0x500 to 0x5000 (available memory not used for kernel or bootloader)
memory_map:
	xor ebx, ebx
	mov di, 0x500
; zero the memory between 0x0500 and 0x5000
.clear:
	mov [di], ebx
	add di, 4
	cmp di, 0x5000
	jb .clear

; initialize di to the start of the buffer (0x0500)
	mov di, 0x500
	mov edx, 0x534D4150	; 'SMAP'
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
	cmp di, 0x5000
	jb .lp ; Still have buffer space
.done:
	ret
