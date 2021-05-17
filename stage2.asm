	BITS 16
	ORG 0x0000

STRUC bootsect
	.jmp_code		resb 3
	.oem_id			resb 8
	.BytesPerSector		resw 1
	.SectorsPerCluster	resb 1
	.ReservedSectors	resw 1
	.TotalFATs		resb 1
	.MaxRootEntries		resw 1
	.NumberOfSectors	resw 1
	.MediaDescriptor	resb 1
	.SectorsPerFAT		resw 1
	.SectorsPerTrack	resw 1
	.SectorsPerHead		resw 1
	.HiddenSectors		resd 1
	.TotalSectors		resd 1
	.BigSectorsPerFAT	resd 1
	.Flags			resw 1
	.FSVersion		resw 1
	.RootDirectoryStart	resd 1
	.FSInfoSector		resw 1
	.BackupBootSector	resw 1
				resb 12 ; Reserved
	.DriveNumber		resb 1
	.ReservedByte		resb 1
	.Signature		resb 1 ; 0x29
	.VolumeID		resd 1
	.VolumeLabel		resb 11
	.SystemID		resb 8
ENDSTRUC

STRUC bitmapheader
; BITMAPFILEHEADER
	.bfType 		resw 1
	.bfSize 		resd 1
				resw 2 ; Reserved
	.bfOffBits 		resd 1
; BITMAPCOREHEADER
	.biSize 		resd 1
	.biWidth 		resd 1
	.biHeight 		resd 1
	.biPlanes 		resw 1
	.biBitCount 		resw 1
; extra from BITMAPINFOHEADER
	.biCompression		resd 1
	.biSizeImage		resd 1
	.biXPelsPerMeter	resd 1
	.biYPelsPerMeter	resd 1
	.biClrUsed		resd 1
	.biClrImportant		resd 1
ENDSTRUC

STRUC dirFileEntry
	.name		resb 8
	.extension	resb 3
	.attr		resb 1
			resb 10
	.timestamp	resd 1
	.cluster	resw 1
	.fileSize	resd 1
ENDSTRUC

STRUC FatFile
	.firstCluster		resw 1
	.filePointer		resw 1
	.currentClusterNumber	resw 1
	.currentClusterLBA	resw 1
	.operationSize		resw 1
	.operationOffset	resw 1
ENDSTRUC

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

	call InitializeFat
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
	mov al, [ds:si]
	test al, al
	je .end_of_directory

	; Skip LFN entries
	cmp BYTE [ds:si + 11], 0x0f
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
	; SI should be pointing at the file entry in sector buffer
	; ES and DS should be already set
	mov di, fileEntry
	mov cx, 32
	cld
	rep movsb ; copy cx bytes ds:si -> es:di

	call SwitchToGraphicMode

	mov di, logo
	mov si, fileEntry
	mov ax, 0xffff
	mov [ds:di + FatFile.currentClusterNumber], ax
	xor ax, ax
	mov [ds:di + FatFile.filePointer], ax
	mov ax, WORD [ds:si + dirFileEntry.cluster]
	mov [ds:di + FatFile.firstCluster], ax
	xor ax, ax
	call f_seek

	mov si, sectBuffer
	mov ax, WORD [ds:si + bitmapheader.bfOffBits]
	mov WORD [bmpDataOffset], ax
	mov ax, WORD [ds:si + bitmapheader.biWidth]
	mov WORD [bmpWidth], ax
	mov ax, WORD [ds:si + bitmapheader.biHeight]
	mov WORD [bmpHeight], ax
	mov ax, WORD [ds:si + bitmapheader.biBitCount]
	shr ax, 3 ; In bytes
	mul WORD [bmpWidth]
	add ax, 3
	and ax, 0xfff8
	mov WORD [bmpScanline], ax

	mov ax, WORD [bmpDataOffset]
	mov di, logo
	call f_seek

	mov bx, ax
	mov ax, WORD [sectBuffer + bx]
	mov WORD [bmpTransparent], ax
	mov ax, WORD [sectBuffer + bx + 2]
	mov WORD [bmpTransparent + 2], ax

	mov si, 1024
	mov di, 0
.bitmapLoop:
	push si
	push di
	mov di, logo
	mov cx, WORD [bmpScanline]
	mov bx, scanline
	call f_read
	pop di
	pop si

	mov cx, si
	sub cx, WORD [bmpWidth]
	sub cx, 10
	mov dx, 127
	sub dx, di
	call StartPixel

	mov cx, WORD [bmpWidth]
	mov bx, scanline
.lineCopy:
	mov ax, WORD [es:bx]
	mov dx, WORD [es:bx+2]
	cmp ax, WORD [bmpTransparent]
	jne .copyPixel
	cmp dx, WORD [bmpTransparent + 2]
	jne .copyPixel
	jmp .nextPixel
.copyPixel:
	mov WORD [gs:bp], ax
	mov WORD [gs:bp+2], dx
.nextPixel:
	add bx, 4
	add bp, 4
	loop .lineCopy
	inc di
	cmp di, WORD [bmpHeight]
	jb .bitmapLoop

end_read:
	call WaitAnyKey
	jmp DoReboot

	; TODO:
	; - Load and jump into the PE
	; - Enter protected mode or leave it to kernel?



;;-----------------------------------------------------------------------------------------------------------


SwitchToGraphicMode:
	push ax
	push bx
	; Set VESA mode 0x118 (1024x768, 32-bit)
	mov ax, 0x4F02
	mov bx, 0x0118 ; 0x4118 for linear memory (no banking)
	int 0x10
	cmp ax, 0x004F
	je .vesa_ok
	jmp .return

.vesa_ok:
	; Set default bank
	xor dx, dx
	mov WORD [bankNumber], dx
	call SetBank
.return:
	pop bx
	pop ax
	ret

InitializeFat:
	mov bx, fatBuffer
	mov ah, 0x02
	mov al, 0x01
	mov cx, 0x0001
	xor dh, dh
	mov dl, BYTE [driveNumber]
	int 0x13
	jc .error

	mov ax, WORD [es:fatBuffer + bootsect.BytesPerSector]
	mov WORD [bytesPerSector], ax
	mov al, BYTE [es:fatBuffer + bootsect.SectorsPerCluster]
	mov BYTE [sectorsPerCluster], al
	mov ax, WORD [es:fatBuffer + bootsect.ReservedSectors]
	mov WORD [reservedSectors], ax
	mov al, BYTE [es:fatBuffer + bootsect.TotalFATs]
	mov BYTE [numberOfFat], al
	mov ax, WORD [es:fatBuffer + bootsect.SectorsPerTrack]
	mov WORD [sectorsPerTrack], ax
	mov ax, WORD [es:fatBuffer + bootsect.SectorsPerHead]
	mov WORD [sectorsPerHead], ax
	mov ax, WORD [es:fatBuffer + bootsect.BigSectorsPerFAT]
	mov WORD [sectorsPerFat], ax
	mov ax, WORD [es:fatBuffer + bootsect.RootDirectoryStart]
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

	movzx ax, BYTE [sectorsPerCluster]
	mul WORD [bytesPerSector]
	mov WORD [bytesPerCluster], ax

	mov ax, 0xffff
	mov WORD [fatCurrentSector], ax

	clc
.error:
	ret

; Moves file pointer to AX and reads the sector into sectBuffer
; On return AX contains the position in sector.
; DI points to a FatFile structure
f_seek:
	push dx
	push cx
	push bx
	mov [ds:di + FatFile.filePointer], ax
	; Divide the offset by cluster size to get cluster number, remainder is the cluster offset
	xor dx, dx
	div WORD [bytesPerCluster] ; AX - cluster number, DX - cluster offset
	push dx
	cmp ax, WORD [es:di + FatFile.currentClusterNumber]
	je .readSector
	; Convert the "cluster number" into actual cluster number from FAT.
	mov cx, ax
	mov ax, [es:di + FatFile.firstCluster]
	;call DisplayHex16
	call ClusterChain
	mov WORD [es:di + FatFile.currentClusterNumber], ax
	;call DisplayHex16
.readSector:
	; Divide the cluster offset by sector size to get sector number (inside of cluster), remainder is the offset inside of sector.
	pop ax
	xor dx, dx
	div WORD [bytesPerSector]
	push dx
	; Convert cluster number into sector (with ClusterLBA) and add the sector number, then read the sector.
	mov bx, ax
	mov ax, WORD [es:di + FatFile.currentClusterNumber]
	call ClusterLBA
	add ax, bx
	mov bx, sectBuffer
	mov cx, 1
	call ReadSector
	pop ax
	pop bx
	pop cx
	pop dx
	ret

; Reads CX bytes from file into buffer pointed by ES:BX
; DI points to a FatFile structure
f_read:
	push si
	push dx
	push cx
	push bx
	push ax
	mov WORD [ds:di + FatFile.operationSize], cx
	xor ax, ax
	mov WORD [ds:di + FatFile.operationOffset], ax
.loopRead:
	mov ax, WORD [ds:di + FatFile.filePointer]
	call f_seek
	; ax contains the offset in sector
	mov cx, WORD [bytesPerSector]
	sub cx, ax

	cmp cx, WORD [ds:di + FatFile.operationSize]
	jb .moreThanSector
	mov cx, WORD [ds:di + FatFile.operationSize]
.moreThanSector:
	sub WORD [ds:di + FatFile.operationSize], cx
	add WORD [ds:di + FatFile.filePointer], cx

	push di
	mov di, bx
	add bx, cx
	mov si, sectBuffer
	add si, ax
	cld
	rep movsb
	pop di

	mov ax, WORD [ds:di + FatFile.operationSize]
	test ax, ax
	jnz .loopRead

	pop ax
	pop bx
	pop cx
	pop dx
	pop si
	ret

; Gets the Nth cluster in file chain
; The first cluster is AX, the number of hops is in CX.
ClusterChain:
	test cx, cx
	jz .return
	push bx
.loopCluster:
	call NextCluster
	loop .loopCluster
	pop bx
.return:
	ret

; Gets the next cluster in chain for cluster AX.
; Full cluster number ends up in register pair BX:AX
; If BX:AX contains 0FFF:FFFF, it means it's the last cluster in chain.
NextCluster:
	push cx
	push ax
	shr ax, 7 ; TODO: do proper math instead of assuming it's 128 clusters in FAT sector.
	cmp ax, WORD [fatCurrentSector]
	je .sectorOK
	mov WORD [fatCurrentSector], ax
	add ax, WORD [fatStart]
	mov bx, fatBuffer
	mov cx, 1
	call ReadSector
.sectorOK:
	pop ax
	mov bx, ax
	and bx, 0x01ff
	shl bx, 2
	mov ax, [es:fatBuffer + bx]
	mov bx, [es:fatBuffer + bx + 2]
	and bx, 0x0fff
	pop cx
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
	push di
	push dx
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
	pop cx
	pop bx
	pop ax
	add bx, WORD [bytesPerSector]
	inc ax
	loop .main

	pop dx
	pop di
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

; Prints cx bytes from es:si as an array of hex values
DisplayHexLine:
	push cx
.printByte:
	test cx, cx
	jz .done
	mov al, BYTE[es:si]
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

; Prints a single word in AX as a hex value.
DisplayHex16:
	push ax
	push bx
	mov bx, ax
	shr ax, 8
	call DisplayHex
	mov ax, bx
	call DisplayHex
	pop bx
	pop ax
	ret

; Prints a single byte in AL as hex value.
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

	; FAT variables
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
	; helper variables
	bytesPerCluster resw 1
	fatCurrentSector resw 1

	; BMP variables
	bmpDataOffset resw 1
	bmpWidth resw 1
	bmpHeight resw 1
	bmpScanline resw 1
	bmpTransparent resd 1

	logo resb FatFile_size

	; buffers
	fileEntry resb 32
	fatBuffer resb 512 ; Buffer for general FAT operations
	sectBuffer resb 512 ; File and directory buffer
	scanline resb 256
