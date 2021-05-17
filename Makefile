default: all

install:
	sudo dd conv=notrunc if=./stage1.bin of=/var/stick.bin bs=512
	sudo cp ./stage2.bin /mnt/stick/init.bin

.PHONY: all clean

stage1.bin: stage1.asm
	nasm -w+all -f bin -o stage1.bin stage1.asm

stage2.bin: stage2.asm
	nasm -w+all -f bin -o stage2.bin stage2.asm

all: stage1.bin stage2.bin

clean:
	rm -f stage1.bin
	rm -f stage2.bin
	rm -f padding.bin
	rm -f bootloader.bin
