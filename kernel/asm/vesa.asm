%include "asm/vesa.inc"
[section .text]
[BITS 16]
vesa:
.getcardinfo:
	; Get SuperVGA information
	; ax = 4F00
	; es:di - pointer to buffer
	mov ax, 0x4F00
	mov di, VBECardInfo
	int 0x10

	; if ok, ax should be 4F
	cmp ax, 0x4F
	je .edid

	; error
	mov eax, 1
	ret

.edid:
	; info filled, check for EDID
	cmp dword [.required], 0	; if both required x and required y are set, forget this
	jne near .findmode
	; Read Extended Display Identification Data (EDID)
	; ax = 4F15
	; bl = 1
	; es:di = EDID buffer
	mov ax, 0x4F15
	mov bl, 1
	mov di, VBEEDID
	int 0x10	; call function

	; if ok, ax should be 4F
	cmp ax, 0x4F
	jne near .noedid

	xor di, di	; zero di
.lp:
	xor cx, cx
	; read first byte of standard timing info into cl
	mov cl, [di+VBEEDID.standardtiming]
	; compute horizontal resolution
	shl cx, 3
	add cx, 248
	push ecx

	; print it
	call decshowrm

	; print 'x'
	mov al, 'x'	
	call charrm

	pop ecx
	mov bx, cx	; cx and bx now hold the horizontal resolution
	inc di	; move di to point to aspect ratio
	mov al, [di+VBEEDID.standardtiming]	; load it into al
	and al, 11000000b	; extract the leftmost 2 bits

	; now we compute vertical resolution based on horizontal and aspect ratio

	; check if 4:3
	cmp al, VBEEDID.aspect.4.3
	jne .not43

	; it's 4:3, we multiply cx by 3 and divide by 4 (= shr 2)
	mov ax, 3
	mul cx
	mov cx, ax
	shr cx, 2
	jmp .gotres

.not43:
	; not 4:3, check 5:4
	cmp al, VBEEDID.aspect.5.4
	jne .not54

	; it's 5:4, multiply cx by 4 (= shl 2) and divide by 5
	shl cx, 2
	mov ax, cx
	mov cx, 5
	xor dx, dx	; now dx:ax hold 4x[hor. res.] (required for 16-bit division)
	div cx
	mov cx, ax	; copy result back to cx
	jmp .gotres

.not54:
	; not 5:4, check 16:10
	cmp al, VBEEDID.aspect.16.10
	jne .not1610

	; it's 16:10, multiply by 5 and divide by 8 (= shr 3)
	mov ax, 5
	mul cx
	mov cx, ax
	shr cx, 3
	jmp .gotres

.not1610:
	; not 16:10, it has to be 16:9 so multiply by 9 and divide by 16 (= shr 4)
	mov ax, 9
	mul cx
	mov cx, ax
	shr cx, 4

; now we have horizontal resolution in bx and vertical in cx
.gotres:
	call decshowrm 	; print vertical resolution
	; print " is supported"
	mov si, .edidmsg
	call printrm

	; increase di to point to the next record
	inc di

	; go to the beginning, unless we left the struct
	cmp di, 8
	jb .lp

	jmp .findmode

.noedid:
	; EDID not supported, print info
	mov si, .noedidmsg
	call printrm
	jmp .findmode

 .resetlist:
	;if needed, reset mins/maxes/stuff
	xor cx, cx
	mov [.minx], cx
	mov [.miny], cx
	mov [.requiredx], cx
	mov [.requiredy], cx
	mov [.requiredmode], cx

.findmode:
	; load segment and offset of video mode
	mov	si, [VBECardInfo.videomodeptr]
	mov ax, [VBECardInfo.videomodeptr+2]
	mov fs, ax
	sub si, 2	; to balance adding 2 below
	; if requiredmode is nonzero, we just assume we found it and it's ok
	mov cx, [.requiredmode]
	test cx, cx
	jnz .getmodeinfo
.searchmodes:
	add si, 2	; go to the next record
	mov cx, [fs:si]	; read mode code
	cmp cx, 0xFFFF	; FFFF means it's the end of the list
	jne .getmodeinfo ; if list is not finished, read mode info

	; if goodmode is still 0, we reset everything
	cmp word [.goodmode], 0
	je .resetlist
	jmp .findmode	; we traversed the entire list, back to the beginning
.getmodeinfo:
	push esi
	; read information about mode
	; cx = mode code
	; ax = 4F01
	; es:di = buffer
	mov [.currentmode], cx
	mov ax, 0x4F01
	mov di, VBEModeInfo
	int 0x10	; call function

	pop esi
	; if ok, ax should be 4F
	cmp ax, 0x4F
	je .foundmode

	; error
	mov eax, 1
	ret

.foundmode:
	; a mode was found, check its properties
	; check minimum values, really not minimums from an OS perspective but ugly for users

	; if color depth below 32 bits, we continue searching
	cmp byte [VBEModeInfo.bitsperpixel], 32
	jb .searchmodes

.testx:
	mov cx, [VBEModeInfo.xresolution]
	; if we require some x resolution, check it, else continue
	cmp word [.requiredx], 0
	je .notrequiredx

	; check if the resolution equals required
	cmp cx, [.requiredx]
	je .testy
	; if not, continue searching
	jmp .searchmodes

.notrequiredx:
	; if below minimum, continue searching
	cmp cx, [.minx]
	jb .searchmodes

.testy:
	mov cx, [VBEModeInfo.yresolution]
	; if we require some y resolution, check it, else continue
	cmp word [.requiredy], 0
	je .notrequiredy

	; check if the resolution equals required
	cmp cx, [.requiredy]
	; if not, continue searching
	jne .searchmodes	; as if there weren't enough warnings, USE WITH CAUTION
	; if x was also required, everything ok, go to setting the mode
	cmp word [.requiredx], 0
	jnz .setmode
	; if x was not required, we just handle this mode as an appropriate one
	jmp .testgood

.notrequiredy:
	; if below minimum, continue searching
	cmp cx, [.miny]
	jb .searchmodes

.testgood:
	; mode passed initial tests
	mov cx, [.currentmode]
	mov [.goodmode], cx	; save it as a good one

	; print mode info
	push esi
	mov cx, [VBEModeInfo.xresolution]	; horizontal res
	call decshowrm
	mov al, 'x'
	call charrm
	mov cx, [VBEModeInfo.yresolution]	; vertical res
	call decshowrm
	mov al, '@'
	call charrm
	xor ch, ch
	mov cl, [VBEModeInfo.bitsperpixel]	; bits per pixel
	call decshowrm

	; print "Is this OK?"
	mov si, .modeok
	call printrm

	; read a character from the keyboard
	xor ax, ax
	int 0x16
	pop esi
	; if the character is not 'y' (meaning ok), continue searching
	cmp al, 'y'
	jne .searchmodes

.setmode:
	; mode is chosen, now set it
	mov bx, [.currentmode]
	cmp bx, 0
	je .nomode	; somehow we got here without choosing a mode

	; set the mode
	or bx, 0x4000
	mov ax, 0x4F02
	int 0x10
.nomode:
	; if everything went ok, ax should be 4F
	cmp ax, 0x4F
	je .returngood

	; error
	mov eax, 1
	ret

.returngood:
	; zero eax and return
	xor eax, eax
	ret

.minx dw 1024
.miny dw 768
.required:
.requiredx dw 0	;USE THESE WITH CAUTION
.requiredy dw 0
.requiredmode dw 0

.noedidmsg db "EDID not supported.",10,13,0
.edidmsg	db " is supported.",10,13,0
.modeok db 10,13,"Is this OK?(y/n)",10,13,0

.goodmode dw 0
.currentmode dw 0

; useful functions

; print number as decimal
; cx - number to print
decshowrm:
	push cx
	push dx
	mov ax, cx	; the number is in ax
	mov cx, 10	; we will be dividing by that
	push word 0	; this will mark that we should stop popping
.lp:
	xor dx, dx	; zero dx for 16-bit division
	div cx		; now ax = ax/10, dx = ax % 10
	add dl, '0'	; convert dl to a digit
	push dx		; and save it on the stack
	cmp ax, 0	; if we reached 0, we can start printing
	je .print
	jmp .lp		; if not, calculate next digit
.print:
	pop ax		; pop previously saved digit
	test al, al	; check if 0
	jz .return	; if yes, we finished printing
	call charrm ; print character
	jmp .print  ; and loop
.return:
	pop dx
	pop cx
	ret


; printing function
; si - address of the null-terminated string to print
printrm:
	mov al, [si]	; load current character into al
	test al, al		; check if it's 0
	jz .return		; if 0, return
	call charrm 	; print character
	inc si			; go to the next one
	jmp printrm 	; and loop
.return:
	ret

; print character supplied in al
charrm: 
	mov bx, 7
	mov ah, 0xE
	int 10h
	ret
