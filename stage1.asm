	BITS 16
	ORG 0x0000

	jmp short rm_start
	nop

	oem_id			db	"pseudoOS"
	BytesPerSector		dw	0x0200
	SectorsPerCluster	db	0x08
	ReservedSectors		dw	0x0020
	TotalFATs		db	0x02
	MaxRootEntries		dw	0x0000
	NumberOfSectors		dw	0x0000
	MediaDescriptor		db	0xF8
	SectorsPerFat		dw	0x0000
	SectorsPerTrack		dw	0x003F
	SectorsPerHead		dw	0x00FF
	HiddenSectors		dd	0x00000000
	TotalSectors		dd	0x00400000
	BigSectorsPerFAT	dd	0x00000FF8
	Flags			dw	0x0000
	FSVersion		dw	0x0000
	RootDirectoryStart	dd	0x00000002
	FSInfoSector		dw	0x0001
	BackupBootSector	dw	0x0006
	TIMES 12 db 0
	DriveNumber		db	0x80
	ReservedByte		db	0x01
	Signature		db	0x29
	VolumeID		dd	0xFFFFFFFF
	VolumeLabel		db	"QUASI  BOOT"
	SystemID		db	"FAT32   "

rm_start:
	cli
	xor ax, ax
	mov ss, ax
	mov sp, 0x4000

	mov ax, 0x07C0
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax
	sti

	; Move cursor to the corner
	mov ah, 0x02
	xor bx, bx
	xor dx, dx
	int 0x10

	; Clear screen
	mov ah, 0x06
	xor al, al
	xor bx, bx
	mov bh, 0x07
	xor cx, cx
	mov dh, 24
	mov dl, 79
	int 0x10

	; Enable A20 gate
	in al, 0x92
	or al, 2
	out 0x92, al

	; Keep size of cluster in cx
	mov cx, WORD[SectorsPerCluster]

	; Calculate the data start sector and keep it in ax
	xor ax,ax
	mov al, BYTE[TotalFATs]
	mul WORD[BigSectorsPerFAT]
	add ax, WORD[ReservedSectors]
	mov WORD[dataSector], ax

	; Read the first cluster of root directory
	mov ax, WORD[RootDirectoryStart];
	call ClusterLBA
	mov bx, 0x0200
	call ReadSectors

	; Look for the stage2 blob name.
	mov di, 0x0200 - 0x20
	mov bx, 8*512/32
next_name:
	add di, 0x20
	mov al, BYTE[di]
	test al,al
	jz next_name

	mov cx, 11
	push di
	mov si, fileName
	cld
	rep cmpsb
	setz al

	pop di
	test al,al
	jnz found_file
	dec bx
	jnz next_name

	; If we failed to find the file, just display message and wait with reset till user presses any key.
	mov si, msgNotFound
	call DisplayMessage

	call WaitAnyKey
	jmp DoReboot

	; Load the file (we assume it fits into 1 cluster)
found_file:
	mov dx, WORD[di + 0x1A]
	mov WORD[cluster], dx

	mov ax, 0x0100
	mov es, ax
	xor bx, bx

	mov cx, 0x0008
	mov ax, WORD[cluster]
	call ClusterLBA
	call ReadSectors
	mov si, msgCRLF
	call DisplayMessage

	; Now jump to the loaded file.
	mov dl, BYTE [DriveNumber]
	push WORD 0x0100
	push WORD 0x0000
	retf

WaitAnyKey:
	xor ah, ah
	int 0x16
	ret

DoReboot:
	mov ax, 0x0040
	mov ds, ax
	mov WORD[0x0072], 0x0000
	jmp 0xFFFF:0x0000

DisplayMessage:
	mov ah, 0x0E
print:
	mov al, BYTE[si]
	test al, al
	jz done
	int 0x10
	inc si
	jmp print
done:
	ret

ReadSectors:
.main:
	mov di, 5
.sectorloop:
	push ax
	push bx
	push cx
	call LbaChs
	mov ah, 0x02
	mov al, 0x01
	mov ch, [absoluteTrack]
	mov cl, [absoluteSector]
	mov dh, [absoluteHead]
	mov dl, [DriveNumber]
	int 0x13
	jnc .success
	xor ax,ax
	int 0x13
	dec di
	pop cx
	pop bx
	pop ax
	jnz .sectorloop
	jmp DoReboot
.success:
	mov ah, 0x0E
	mov al, '.'
	int 0x10
	pop cx
	pop bx
	pop ax
	add bx, WORD[BytesPerSector]
	inc ax
	loop .main
	ret

LbaChs:
	xor dx, dx
	div WORD [SectorsPerTrack]
	inc dl
	mov [absoluteSector], dl
	xor dx, dx
	div WORD[SectorsPerHead]
	mov [absoluteHead], dl
	mov [absoluteTrack], al
	ret

ClusterLBA:
	sub ax, 0x0002
	xor cx, cx
	mov cl, [SectorsPerCluster]
	mul cx
	add ax, WORD[dataSector]
	ret

bss:
	absoluteSector	db 0x00
	absoluteHead	db 0x00
	absoluteTrack	db 0x00
	cluster		dw 0x0000
	dataSector	dw 0x0000
data:
	fileName db "INIT    BIN"
	msgNotFound db "Stage 2 not found", 0x0d, 0x0a, 0x00
	msgFailure db 0x0d, 0x0a, "Stage 1 failed...", 0x0d, 0x0a, 0x00
	msgCRLF db 0x0D, 0x0A, 0x00

	TIMES 510 - ($-$$) DB 0
	DW 0xAA55
