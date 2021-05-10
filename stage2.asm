	BITS 16
	ORG 0x0000

stage2:
	cli
	mov ax, 0x0100
	mov ds,ax
	mov es,ax
	mov fs,ax
	mov gs,ax
	sti

	mov BYTE [driveNumber], dl

	mov si, msgStage2
	call DisplayMessage

	call initialize_fat
	jnc boot_read_ok

	push ax

	mov si, msgReadError
	call DisplayMessage

	pop ax
	mov al, ah
	call DisplayHex

	mov si, msgCrLf
	call DisplayMessage

	jmp end_read

boot_read_ok:
	mov ax, WORD [rootStart]
	call ClusterLBA

	mov bx, sectBuffer
	mov cx, 1
	call ReadSector

	mov si, sectBuffer
	xor cx, cx
.next:
	mov al, [es:si]
	test al, al
	je .end_of_directory

	; Skip LFN entries
	cmp BYTE [es:si + 11], 0x0f
	je .continue

	mov cx, 11
	mov di, logoName
	push si
	cld
	rep cmpsb
	pop si
	jnz .continue
	jmp .found

.continue:
	add si, 32
	mov bx, WORD [entriesPerCluster]
	cmp cx, bx
	jl .next

.end_of_cluster:
	mov si, msgMultiCluster
	call DisplayMessage
	call WaitAnyKey
	jmp DoReboot

.end_of_directory:
	mov si, msgFileNotFound
	call DisplayMessage
	call WaitAnyKey
	jmp DoReboot

.found:
	; TODO: Copy the directory entry
	mov ax, WORD [es:si + 26]
	push ax
	;call crlf
	;call DisplayHex16
	;call crlf
	pop ax
	call ClusterLBA
	mov bx, sectBuffer
	mov cx, 1
	call ReadSector

	;call crlf
	;mov si, sectBuffer
	;mov cx, 16
	;call DisplayHexLine

end_read:
	call WaitAnyKey

	; Set VESA mode 0x118 (1024x768, 32-bit)
	mov ax, 0x4F02
	mov bx, 0x0118 ; 0x4118 for linear memory (no banking)
	int 0x10
	cmp ax, 0x004F
	je vesa_ok
	jmp do_reboot

vesa_ok:
	; Set default bank
	xor dx, dx
	mov WORD [bankNumber], dx
	call SetBank

	; TODO: Load and draw image?

do_reboot:
	call WaitAnyKey
	jmp DoReboot

	; TODO:
	; - Load and jump into the PE
	; - Enter protected mode or leave it to kernel?

initialize_fat:
	mov bx, sectBuffer
	mov ah, 0x02
	mov al, 0x01
	mov cx, 0x0001
	xor dh, dh
	mov dl, BYTE [driveNumber]
	int 0x13
	jc .error

	mov ax, WORD [es:sectBuffer + 11]
	mov WORD [bytesPerSector], ax
	mov al, BYTE [es:sectBuffer + 13]
	mov BYTE [sectorsPerCluster], al
	mov ax, WORD [es:sectBuffer + 14]
	mov WORD [reservedSectors], ax
	mov al, BYTE [es:sectBuffer + 16]
	mov BYTE [numberOfFat], al
	mov ax, WORD [es:sectBuffer + 24]
	mov WORD [sectorsPerTrack], ax
	mov ax, WORD [es:sectBuffer + 26]
	mov WORD [sectorsPerHead], ax
	mov ax, WORD [es:sectBuffer + 36]
	mov WORD [sectorsPerFat], ax
	mov ax, WORD [es:sectBuffer + 44]
	mov WORD [rootStart], ax

	mov ax, WORD [reservedSectors]
	mov WORD [fatStart], ax

	mov al, BYTE [numberOfFat]
	mul WORD [sectorsPerFat]
	mov bx, WORD [fatStart]
	add ax, bx
	mov WORD [dataStart], ax

	movzx ax, BYTE [sectorsPerCluster]
	shl ax, 4
	mov WORD [entriesPerCluster], ax

	;mov ax, 0x0e00 + '?'
	;int 0x10

	clc
.error:
	ret

; DX = Y
; CX = X
; Prepares the GS:BP register pair for writing the pixels
StartPixel:
	push ax
	push dx
	shr dx, 4
	cmp dx, WORD [bankNumber]
	je .skipBank
	call SetBank
	mov WORD [bankNumber], dx
.skipBank:
	pop dx
	mov ax, dx
	and ax, 0x0f
	shl ax, 10
	add ax, cx
	shl ax, 2
	mov bp, ax
	mov ax, 0xA000
	mov gs, ax
	pop ax
	ret

; DX contains the bank number
SetBank:
	push ax
	push bx
	xor bx, bx
	mov ax, 0x4F05
	int 0x10
	pop bx
	pop ax
	ret

; Reads CX sectors, starting from AX to memory buffer starting at address ES:BX
ReadSector:
.main:
	mov di, 0x0005
.sector_loop:
	push ax
	push bx
	push cx
	call LBAtoCHS
	mov ah, 0x02
	mov al, 0x01
	mov dl, BYTE [driveNumber]
	int 0x13
	jnc .success
	xor ax, ax
	int 0x13
	pop cx
	pop bx
	pop ax
	dec di
	jnz .sector_loop

	mov si, msgReadError
	call DisplayMessage
	call WaitAnyKey
	jmp DoReboot

.success:
	mov ax, 0x0E00 + '.'
	int 0x10
	pop cx
	pop bx
	pop ax
	add bx, WORD [bytesPerSector]
	inc ax
	loop .main
	ret

LBAtoCHS:
	xor dx, dx
	div WORD [sectorsPerTrack]
	inc dl
	mov cl, dl
	xor dx, dx
	div WORD [sectorsPerHead]
	mov ch, al
	mov dh, dl
	ret

ClusterLBA:
	sub ax, 2
	movzx cx, BYTE [sectorsPerCluster]
	mul cx
	add ax, WORD [dataStart]
	ret

DisplayMessage:
	mov ah, 0x0E
.print:
	mov al, BYTE[si]
	test al, al
	jz .done
	int 0x10
	inc si
	jmp .print
.done:
	ret

crlf:
	push ax
	mov ax, 0x0E0D
	int 0x10
	mov ax, 0x0E0A
	int 0x10
	pop ax
	ret

DisplayHexLine:
	push cx
.printByte:
	test cx, cx
	jz .done
	mov al, BYTE[si]
	call DisplayHex
	mov ah, 0x0E
	mov al, ' '
	int 0x10
	inc si
	dec cx
	jmp .printByte
.done:
	push si
	mov si, msgCrLf
	call DisplayMessage
	pop si
	pop cx
	ret

DisplayHex16:
	push bx
	mov bx, ax
	shr ax, 8
	call DisplayHex
	mov ax, bx
	call DisplayHex
	pop bx
	ret

DisplayHex:
	push bx
	mov bl, al
	shr al, 4
	call .printNibble
	mov al, bl
	and al, 0x0f
	call .printNibble
	mov al, bl
	pop bx
	ret
.printNibble:
	cmp al, 10
	jl .digit
	add al, 'a' - 10
	jmp .doPrint
.digit:
	add al, '0'
.doPrint:
	mov ah, 0x0E
	int 0x10
	ret

WaitAnyKey:
        xor ah, ah
        int 0x16
        ret

DoReboot:
        mov ax, 0x0040
        mov ds, ax
        mov WORD[0x0072], 0x0000
        jmp 0xFFFF:0x0000

section .data align=16
	msgCrLf db 0x0d, 0x0a, 0x00
	msgStage2 db "Stage 2!", 0x0d, 0x0a, 0x00
	msgReadError db "Read error: ", 0x00
	msgFileNotFound db "File not found", 0x0d, 0x0a, 0x00
	msgMultiCluster db "Directory too big", 0x0d, 0x0a, 0x00
	logoName db "LOGO    BMP", 0x00

section .bss align=16
	bankNumber resw 1
	cursorX resw 1
	cursorY resw 1

	bytesPerSector resw 1
	sectorsPerCluster resb 1
	reservedSectors resw 1
	numberOfFat resb 1
	sectorsPerFat resw 1
	sectorsPerTrack resw 1
	sectorsPerHead resw 1
	rootDirStart resw 1
	fatStart resw 1
	dataStart resw 1
	rootStart resw 1
	entriesPerCluster resw 1
	driveNumber resb 1
	fileEntry resb 32
	sectBuffer resb 512
