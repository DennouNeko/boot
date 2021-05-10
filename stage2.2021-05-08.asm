	ORG 0x0000

stage2:
	cli
	mov ax, 0x0100
	mov ds,ax
	mov es,ax
	mov fs,ax
	mov gs,ax
	sti

	mov si, msgStage2
	call DisplayMessage

	call WaitAnyKey
	jmp DoReboot

	; TODO:
	; - Load and jump into the PE
	; - Enter protected mode or leave it to kernel?

DisplayMessage:
        mov ah, 0x0E
print:
	mov al, [si]
	test al, al
	jz done
	int 0x10
	inc si
	jmp print
done:
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

data:
	msgStage2 db "Stage 2!", 0x0d, 0x0a, 0x00
