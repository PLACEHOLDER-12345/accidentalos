; AccidentalOS - boot sector
; the bootloader

BITS 16                          ; 16-bit real mode
ORG 0x7C00                       ; bootloader

; THE REAL KERNEL
start:
    CLI                         ; disable interrupts
    MOV ax, STACK_SEG           ; stack at 0x90000
    MOV ss, ax
    MOV sp, 0xFFFF              ; top at 0x9FFFF
    CLD
    STI

    MOV ax, cs
    MOV ds, ax ; temporarily ds = cs
    MOV es, ax ; same for es

    MOV ax, 3                   ; set text mode
    INT 0x10                    ; VGA interrupt

    XOR di, di                  ; Start at offset 0

    MOV si, boot_msg            ; Load message address
.L2:
    LODSB ; MOV al, [ds:si], si++
    TEST al, al                 
    JZ stage2_load              ; end print loop on null

    CMP al, NEWLINE             ; newline
    JE .L3

    MOV ah, 0x0F                ; Set attribute for every char
    CALL print_char
    JMP .L2
.L3: ; newline
    CALL newline
    JMP .L2 ; continue on with the print loop
.L4: ; error pre-VGA because Jcc error doesnt work then
    CLI
    HLT
    JMP .L4

stage2_load:
    MOV ax, 0x800
    MOV es, ax
    XOR bx, bx

    MOV ah, 2 ; request: read sectors and store in memory
    MOV al, 3 ; read 3 sectors = 1.5 KB
    XOR dl, dl ; choose drive A - the floppy
    ; load code from sector 33 - C0H1S1 in CHS
    XOR ch, ch ; cylinder
    MOV cl, 18 ; sector
    XOR dh, dh ; head

    INT 0x13

    JC .L5 ; carry flag means an error happened

    JMP 0x0800:0x0000
.L5:
    CLI
    HLT
    JMP .L5

shutdown: ; done - shutdown
    CLI                         ; Clear interrupts so it stays paused
    HLT                         ; Halt CPU
    JMP $

; HELPERS

print_char: ; print a character in al
    PUSH es
    PUSH ax

    MOV ax, VGA_MEM_START
    MOV es, ax

    POP ax

    MOV ah, 0x0F
    MOV WORD [es:di], ax
    ADD di, 2

    POP es    

    ; update cursor
    PUSH ax
    MOV ax, di
    SHR ax, 1          ; byte offset -> character index
    ; div by 80
    XOR dx, dx
    MOV bx, 80
    DIV bx             ; AX = row, DX = column

    MOV ah, 0x02       ; request: set cursor
    MOV bh, 0
    MOV dh, al         ; row
    MOV dl, dl         ; column (DL = DX low byte)
    INT 0x10
    POP ax
    RET
newline: ; move to a new line (warning: destroy ax)
    MOV ax, di
    XOR dx, dx
    MOV cx, 160
    DIV cx              ; DX = column, AX = row

    SUB di, dx
    ADD di, 160

    RET
boot_msg: db "Starting AccidentalOS...", 10, "Going to kernel...", 10, 0

; constants
BACKSPACE: equ 0x08
NEWLINE: equ 0x0A
CR: equ 0x0D
STACK_SEG: equ 0x9000
VGA_MEM_START: equ 0xB800

times 510 - ($ - $$) db 0       ; Pad to 510 bytes
dw 0xAA55                       ; Boot signature - must have