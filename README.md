# Welcome to AccidentalOS!
A simple 16-bit operating system written using Assembly.

by [PLACEHOLDER-12345](https://github.com/PLACEHOLDER-12345)
with __a bit__ of help from Microsoft Copilot.

---

## How it began

AccidentalOS started as a short 8086 VGA Hello World demo.
I showed it to MS Copilot and then he told me to add more and then

**boom** I have an operating system!!

---

## How to use AccidentalOS

You need:

* QEMU
* NASM
* Python

1. Download the files
2. Assemble the boot: `nasm -f bin boot.s -o boot.bin`
3. Assemble the kernel: `nasm -f bin kernel.s -o kernel.bin`
4. Convert to a floppy image: `python aosmaker.py`
5. Run using QEMU:
```cmd
qemu-system-i386.exe -drive if=floppy,format=raw,file=accidentalos.img -no-reboot -boot a
```

## Give it a star!