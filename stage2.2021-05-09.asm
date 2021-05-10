	ORG 0x0000

stage2:
	cli
	mov ax, 0x0100
	mov ds,ax
	mov es,ax
	mov fs,ax
	mov gs,ax
	sti

	;mov ah, 0x00
	;mov al, 0x13
	;int 0x10
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

	; Set es to be used as segment register for video memory
	mov ax, 0xA000
	mov es, ax

	; TODO: Load and draw image?

	;mov si, msgStage2
	;call DisplayMessage

do_reboot:
	call WaitAnyKey
	jmp DoReboot

	; TODO:
	; - Load and jump into the PE
	; - Enter protected mode or leave it to kernel?

; Prepares the ES:BP register pair for writing the pixels
StartPixel:
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

DisplayMessage:
        mov ax, 0xB800
	mov es, ax
print:
	mov al, [si]
	test al, al
	jz done
	cmp al, 0x0d
	je char_cr
	cmp al, 0x0a
	je char_nl
	call draw_char
	mov ah, BYTE [cursorY]
	mov al, BYTE [cursorX]
	cmp al, 80
	jl char_done1
	xor al, al
	inc ah
	cmp al, 24
	jl char_done1
	; roll up screen?
char_done1:
	mov BYTE [cursorX], al
	mov BYTE [cursorY], ah
	jmp char_done
char_cr:
	xor al, al
	mov BYTE [cursorX], al
	jmp char_done
char_nl:
	inc BYTE [cursorY]
	jmp char_done
char_done:
	inc si
	jmp print
done:
	ret

draw_char:
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
	msgStage2 db "Stage 2!", 0x0d, 0x0a, 0x00

section .bss align=16
	bankNumber resw 1
	cursorX resw 1
	cursorY resw 1
	bootsect resb 512
