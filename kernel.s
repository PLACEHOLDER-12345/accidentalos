; AccidentalOS - kernel.s
; the actual kernel

BITS 16                          ; 16-bit real mode
ORG 0x0000                       ; loaded at 0x0000 by boot sector

stage2_start: ; entry point for stage 2, jumped to by the boot
    CLI
    CLD

    ; flat view
    MOV ax, cs
    MOV ds, ax
    MOV es, ax

    ; stack setup
    MOV ax, STACK_SEG ; stack at 0x90000
    MOV ss, ax
    MOV sp, 0xFFFF ; top at 0x9FFFF

    MOV ax, ss
    CMP ax, STACK_SEG
    JNE error

    STI

    MOV [VGA_cursor], di ; set the cursor to di (was cursor in boot.s)

    ; set si pointer to the boot message
    MOV si, kernel_boot_msg
    CALL print_string

    CALL newline
    JMP terminal_loop

terminal_loop: ; main terminal loop
    MOV BYTE [input_len], 0 ; reset input length

    ; print prompt "> "
    MOV al, '>'
    CALL print_char
    MOV al, ' '
    CALL print_char
.L2: ; keyboard input loop
    XOR ah, ah
    INT 0x16            ; wait for key
    ; AL = ASCII, AH = scan code

    ; if key input fails then error
    TEST al, al
    JNZ .L3
    TEST ah, ah
    JNZ .L3
    CALL error
.L3:
    ; enter key
    CMP al, CR
    JE .L4

    ; backspace
    CMP al, BACKSPACE        ; Backspace?
    JE .L5
    CMP ah, 0x0E
    JE .L5

    ; fallback on other control chars - ignore
    CMP al, 0x20
    JB .L2

    ; compare input length to 16 - if too long ignore
    XOR bh, bh
    MOV bl, [input_len]
    CMP bl, 16
    JAE .L2

    ; set the input buffer and increment length
    MOV BYTE [input_buffer + bx], al
    INC bl
    MOV [input_len], bl

    ; echo character
    CALL print_char ; al already set
    JMP .L2

.L4: ; input finished
    ; reset length and buffer
    MOV bl, [input_len]
    XOR bh, bh
    MOV BYTE [input_buffer + bx], 0

    CALL process_command

    ; restart the loop
    CALL newline
    JMP terminal_loop
.L5:
    MOV bl, [input_len]
    CMP bl, 0
    JE .L2 ; nothing to delete

    SUB WORD [VGA_cursor], 4
    JB error ; model/view mismatch
    JBE .L2

    ; decrement input length
    DEC bl
    MOV BYTE [input_len], bl
    ; set null in buffer
    XOR bh, bh
    MOV BYTE [input_buffer + bx], 0
    CALL backspace
    JMP .L2

process_command:
    ; do nothing for now
    RET

shutdown: ; done - shutdown
    CLI                         ; Clear interrupts so it stays paused
    HLT                         ; Halt CPU
    JMP $

; HELPERS

print_char: ; print a character
    ; inputs: al
    ; outputs: none
    ; clobber: none
    PUSH es

    PUSH ax

    ; set es to VGA memory
    MOV ax, VGA_MEM_START
    MOV es, ax

    POP ax

    ; write character to VGA mem with white on black
    MOV ah, 0x0F

    MOV di, [VGA_cursor]

    MOV WORD [es:di], ax
    ; increment cursor
    ADD di, 2
    MOV WORD [VGA_cursor], di

    ; set es back
    POP es    

    PUSH ax
    PUSH dx
    PUSH bx

    ; calculate row and column
    MOV ax, [VGA_cursor]
    SHR ax, 1          ; byte offset -> character index

    MOV bx, ax
    
    ; set low byte of cursor
    MOV dx, 0x3D4
    MOV al, 0x0F ; cursor low byte register
    OUT dx, al

    MOV dx, 0x3D5
    MOV al, bl
    OUT dx, al ; cursor low byte value

    ; high byte

    MOV dx, 0x3D4
    MOV al, 0x0E ; cursor high byte register
    OUT dx, al

    ; send value
    MOV dx, 0x3D5
    MOV al, bh
    OUT dx, al

    POP bx
    POP dx
    POP ax
    RET

print_string: ; print a null-terminated string by repeatedly using print_char
    ; input: si = string pointer
    ; output: nothing
    ; clobber: 

    LODSB
    TEST al, al
    JZ .L8 ; end if null

    CMP al, NEWLINE
    JE .L6 ; newline

    CMP al, CR
    JE .L7 ; carriage return

    CALL print_char
    JMP print_string
.L6: ; newline
    CALL newline
    JMP print_string
.L7: ; carriage return
    CALL carriage_return
    JMP print_string
.L8: ; null terminator, end
    RET

newline: ; move to a new line
    ; input: none
    ; output: none
    ; clobber: ax, dx, cx, di

    ; calculate row and column
    MOV di, [VGA_cursor]

    MOV ax, di
    XOR dx, dx
    MOV cx, 160
    DIV cx              ; DX = column, AX = row

    ; set column to zero
    SUB di, dx
    ADD di, 160

    MOV [VGA_cursor], di

    CMP WORD [VGA_cursor], 160 * 25 ; past the screen?
    JAE .L9

    RET
.L9: ; if last line
    CALL scroll_up
    RET

carriage_return: ; move to the start of the line
    ; input: none
    ; output: none
    ; clobber: ax, di

    MOV di, [VGA_cursor]

    ; calculate row/column
    MOV ax, di
    XOR dx, dx
    MOV cx, 160
    DIV cx              ; DX = column, AX = row

    SUB di, dx

    MOV [VGA_cursor], di

    RET

backspace: ; move the cursor back
    ; inputs: none
    ; outputs: none
    ; clobbers: di

    ; check if we're at the start of video memory
    CMP WORD [VGA_cursor], 2
    JBE .L10     ; can't backspace past start

    PUSH es

    ; set es to memory
    MOV ax, VGA_MEM_START
    MOV es, ax

    MOV di, [VGA_cursor]

    ; write a space to the VGA buffer
    SUB di, 2
    MOV WORD [es:di], 0x0F20

    ; calculate row/column
    MOV ax, di
    SHR ax, 1          ; byte offset -> character index
    XOR dx, dx
    MOV bx, 80
    DIV bx             ; AX = row, DX = column
    ; update cursor
    MOV ah, 0x02       ; request: update cursor
    XOR bh, bh
    MOV dh, al         ; row
    ; dl contains the column
    INT 0x10

    MOV WORD [VGA_cursor], di
.L10:
    POP es
    RET

error: ; error
    ; input: none
    ; output: none
    ; clobbers: si
    MOV si, error_msg
    CALL print_string
.L11:
    HLT
    JMP .L11
scroll_up:
    PUSH si
    PUSH es
    PUSH ds

    MOV ax, VGA_MEM_START
    MOV ds, ax
    MOV es, ax

    CLD

    ; copy lines 2–25 → 1–24
    MOV si, 160
    MOV di, 0
    MOV cx, 80 * 24
    REP MOVSW

    ; clear last line
    MOV ax, 0x0F20
    MOV di, 160 * 24
    MOV cx, 80
    REP STOSW

    ; restore kernel data segment
    POP ds

    ; move cursor to start of last line
    MOV di, 160 * 24
    MOV WORD [VGA_cursor], di

    ; update cursor
    MOV ax, [VGA_cursor]
    SHR ax, 1

    XOR dx, dx
    MOV bx, 80
    DIV bx

    MOV ah, 2
    XOR bh, bh
    MOV dh, al
    INT 0x10

    POP es
    POP si
    RET
strcmp: ; compare strings. 
    ; inputs: si = ptr to string 1 in DS, di = ptr to string 2 in DS
    ; outputs: ax = 1 if equal, ax = 0 if not
    ; clobbers: si, di
.L12:
    ; set al & bl to characters @ si & es:di
    MOV al, [ds:si]
    MOV bl, [ds:di]

    ; check if equal
    CMP al, bl
    JNE .L13

    ; if finished, then al would be null
    CMP al, 0
    JE .L14

    ; increment si, di and try again
    INC si
    INC di
    JMP .L12
.L13: ; unequal
    ; set unequal result
    MOV ax, 0
    RET
.L14: ; equal
    ; set equal result
    MOV ax, 1
    RET

strupr:
    ; inputs: si = ptr to string
    ; outputs: none
    ; clobber: al
    LODSB ; MOV al, [si], si++

    CMP al, 0
    JE .L21

    CMP al, 0x61 ; 'A'
    JB .L22

    CMP al, 0x7A ; 'Z'
    JB .L22

    SUB al, 32 ; convert to uppercase
.L22:
    MOV [si - 1], al ; write back
    JMP strlwr
.L21: ; finished
    RET

strlwr: ; modify a string to have all letters lowercase
    ; inputs: si = ptr to string
    ; outputs: none
    ; clobber: al
    LODSB ; MOV al, [si], si++

    CMP al, 0
    JE .L19

    CMP al, 0x41 ; 'A'
    JB .L20

    CMP al, 0x5A ; 'Z'
    JB .L20

    ADD al, 32 ; convert to lowercase
.L20:
    MOV [si - 1], al ; write back
    JMP strlwr
.L19: ; finished
    RET

putchar:
    CALL print_char
    RET

puts:
    CALL print_string
    CALL newline
    RET

load_file: ; load file and store in the range of 0x80000-0x8FFFF
    ; inputs: si = ptr to filename
    ; outputs: ax = 0 if fail, ax = 1 if success
    ; clobbers: ax, bx, cx, dx, di

    PUSH es ; preserve es
    PUSH di
    PUSH si
    PUSH ds

    ; STEP 1: load the file table into kernel data segment (0x1000-0x7BFF)
    MOV ax, 0x0100
    MOV es, ax
    XOR bx, bx

    ; set up registers for INT 0x13
    MOV ah, 0x02 ; request: read sectors
    MOV al, 15 ; 4 sectors to read
    XOR dl, dl ; from the floppy
    ; load from sector 2 - C0H0S3 in CHS
    XOR ch, ch ; cylinder
    XOR dh, dh ; head
    MOV cl, 3 ; sector

    INT 0x13

    JC error ; if carry flag set, then error

    MOV cx, 240 ; 240 file entries ((15 * 512) / 32)
    XOR di, di ; di = offset in file table
.L15: 
    ; STEP 2: check if file exists
    ; compare filename to entry

    PUSH si
    PUSH di

    ; MOV si, si - si already points to filename, so no need to set
    ; MOV di, di - di contains offset of file table already
    
    CALL strcmp

    POP di
    POP si

    CMP ax, 1
    JE .L16 ; if strings equal load the file

    ADD di, 32 ; move to next file entry
    LOOP .L15

    MOV ax, 0
    JMP .L17
.L16: ; if file name & target are equal
    ; STEP 3: load file into memory

    ; check if file is big
    MOV ax, WORD [es:di + 30] ; offset of byte size
    CMP ax, 0
    JNE .L18

    MOV ax, WORD [es:di + 21] ; starting sector as an LBA to prepare for division
    ; sector = (LBA % 18) + 1
    XOR dx, dx
    MOV bx, 18
    DIV bx

    MOV cl, dl
    INC cl

    ; ax = temp
    ; head & cylinder

    XOR dx, dx
    MOV bx, 2
    DIV bx

    MOV dh, dl
    MOV ch, al
    ; set destination buffer
    MOV ax, FILE_BUFFER
    MOV es, ax
    XOR bx, bx
    ; prepare for INT 0x13
    MOV ah, 2 ; request: read sectors
    MOV al, BYTE [di + 23] ; sectors
    ; cl, ch, dh are already CHS values
    XOR dl, dl ; from the floppy

    INT 0x13
    JC error

    MOV ax, 1
.L17: ; finished
    POP ds
    POP si
    POP di
    POP es
    RET
.L18: ; file too big
    MOV si, file_too_big_msg
    CALL print_string
    XOR ax, ax
    JMP .L17

; DATA
; strings
kernel_boot_msg: db "Kernel load done - ready.", 10, 0
; test string with newline and carriage return
error_msg: db "Error, shutdown.", 0
test_file_name: db "test.txt", 0
file_too_big_msg: db "DAMN! Are you writing a novel?!", 0

; command prompt data
input_buffer: times 17 db 0 ; 16 chars + end null
input_len: db 0

; other data
VGA_cursor: dw 0

; CONSTANTS
BACKSPACE: equ 0x08
NEWLINE: equ 0x0A
CR: equ 0x0D
FILE_BUFFER: equ 0x8000
STACK_SEG: equ 0x9000
VGA_MEM_START: equ 0xB800