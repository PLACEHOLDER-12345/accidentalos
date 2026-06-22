; AccidentalOS - kernel.s
; the actual kernel

BITS 16
ORG 0x0000 ; loaded at 0x0000 by boot sector

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
    MOV si, '>'
    CALL print_char
    MOV si, ' '
    CALL print_char
.L2: ; keyboard input loop
    CALL get_key ; get key input in ax

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

    ; ignore input if buffer full
    XOR bh, bh
    MOV bl, [input_len]
    CMP bl, MAX_BUFFER_LEN
    JAE .L2

    ; set the input buffer and increment length
    MOV BYTE [input_buffer + bx], al
    INC bl
    MOV [input_len], bl

    ; echo character
    XOR ah, ah
    MOV si, ax
    CALL print_char ; al already set
    JMP .L2

.L4: ; input finished
    CALL newline

    ; reset length and buffer
    MOV bl, [input_len]
    XOR bh, bh
    MOV BYTE [input_buffer + bx], 0

    CALL set_arg_counts ; set argc and argv for the command

    CALL process_command

    ; restart the loop
    JMP terminal_loop
.L5:
    MOV bl, [input_len]
    CMP bl, 0
    JE .L2 ; nothing to delete

    ; decrement input length and clear last buffer character
    DEC bl
    MOV BYTE [input_len], bl
    XOR bh, bh
    MOV BYTE [input_buffer + bx], 0
    CALL backspace
    JMP .L2

set_arg_counts:
    PUSH si
    PUSH di
    PUSH bx

    MOV si, input_buffer
    MOV di, argv
    XOR cx, cx
.L28: ; skip spaces & check the end
    MOV al, [si]
    CMP al, 0
    JE .L32
    CMP al, ' '
    JNE .L29
    INC si
    JMP .L28
.L29: ; argument start
    MOV [di], si
    ADD di, 2
    INC cl
.L30: ; argument scan
    MOV al, [si]
    CMP al, 0
    JE .L32
    CMP al, ' '
    JE .L31
    INC si
    JMP .L30
.L31: ; end of argument
    MOV BYTE [si], 0
    INC si
    JMP .L28
.L32: ; finished
    MOV WORD [di], 0 ; terminate argv
    MOV [argc], cl
    POP bx
    POP di
    POP si
    RET

process_command:
    ; we manually compare each command

    MOV si, [argv] ; get pointer to arg 0 (the command)
    CALL strupr

    MOV si, [argv]
    MOV di, command_HELP
    CALL strcmp
    TEST ax, ax
    JZ .L22

    MOV si, [argv]
    MOV di, command_CLEAR
    CALL strcmp
    TEST ax, ax
    JZ .L23
    MOV si, [argv]
    MOV di, command_CLS
    CALL strcmp
    TEST ax, ax
    JZ .L23

    MOV si, [argv]
    MOV di, command_ECHO
    CALL strcmp
    TEST ax, ax
    JZ .L24

    MOV si, [argv]
    MOV di, command_VER
    CALL strcmp
    TEST ax, ax
    JZ .L36

    MOV si, [argv]
    MOV di, command_VERSION
    CALL strcmp
    TEST ax, ax
    JZ .L36

    MOV si, invalid_command_msg
    CALL print_string

    RET
.L22:
    CALL execute_cmd_HELP
    RET
.L23:
    CALL execute_cmd_CLEAR
    RET
.L24:
    CALL execute_cmd_ECHO
    RET
.L36:
    CALL execute_cmd_VER
    RET

execute_cmd_HELP:
    MOV si, help_msg
    CALL print_string
    RET

execute_cmd_CLEAR:
    PUSH es
    PUSH bx

    XOR bx, bx
    MOV ax, 0xB800
    MOV es, ax
.L23: ; clear loop
    MOV WORD [es:bx], 0x0F20 ; write a space
    ADD bx, 2

    CMP bx, 80 * 25 * 2
    JB .L23

    POP bx
    POP es

    MOV WORD [VGA_cursor], 0
    CALL update_cursor
    
    RET

execute_cmd_ECHO: ; print each argument with a space in between, skip command name
    PUSH si
    PUSH di
    PUSH bx

    MOV cl, [argc]
    XOR ch, ch ; argc is a byte, clear high byte
    CMP cl, 1 ; if only command then do nothing
    JBE .L34

    DEC cl ; args to print

    MOV di, argv
    ADD di, 2 ; skip cmd name
.L33: ; loop through args
    MOV si, [di]
    CALL print_string

    ; print a space if not the last arg
    ADD di, 2
    DEC cl

    CMP cl, 0
    JE .L34

    MOV si, ' '
    CALL print_char
    JMP .L33
.L34: ; done
    CALL newline

    POP bx
    POP di
    POP si
    RET

execute_cmd_VER:
    PUSH si

    MOV si, .msg
    CALL print_string

    CALL newline
    POP si
    RET
.msg: db "AOS v0.4.0", 0

shutdown: ; done - shutdown
    CLI                         ; Clear interrupts so it stays paused
    HLT                         ; Halt CPU
    JMP $

; HELPERS

print_char: ; print a character
    ; inputs: si
    ; outputs: none
    ; clobber: ax, di, es
    PUSH es
    PUSH si
    PUSH di

    ; set es to VGA memory
    MOV ax, VGA_MEM_START
    MOV es, ax

    ; write character to VGA mem with white on black
    MOV ax, si
    MOV ah, 0x0F

    MOV di, [VGA_cursor]
    MOV WORD [es:di], ax
    ; increment cursor
    ADD WORD [VGA_cursor], 2

    POP di
    POP si    
    POP es

    CALL update_cursor
    RET

print_string: ; print a null-terminated string by repeatedly using print_char
    ; input: si = string pointer
    ; output: nothing
    ; clobber: 
    PUSH si
    PUSH di
.L35:
    LODSB ; MOV al, [si]; INC si
    TEST al, al
    JZ .L8 ; end if null

    CMP al, NEWLINE
    JE .L6 ; newline

    CMP al, CR
    JE .L7 ; carriage return

    PUSH si
    XOR ah, ah
    MOV si, ax
    CALL print_char
    POP si

    JMP .L35
.L6: ; newline
    CALL newline
    JMP .L35
.L7: ; carriage return
    CALL carriage_return
    JMP .L35
.L8: ; null terminator, end
    POP di
    POP si

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
    ADD di, CHARS_PER_LINE * 2

    MOV [VGA_cursor], di

    CMP WORD [VGA_cursor], CHARS_PER_LINE * 2 * 25 ; past the screen?
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
    MOV cx, CHARS_PER_LINE * 2
    DIV cx              ; DX = column, AX = row

    SUB di, dx

    MOV [VGA_cursor], di

    RET

backspace: ; move the cursor back
    ; inputs: none
    ; outputs: none
    ; clobbers: ax, di

    MOV ax, [VGA_cursor]
    CMP ax, 2
    JB .L10     ; can't backspace past start

    SUB ax, 2
    MOV [VGA_cursor], ax

    PUSH es

    ; set es to VGA memory
    MOV ax, VGA_MEM_START
    MOV es, ax

    MOV di, [VGA_cursor]

    ; clear previous character cell
    MOV WORD [es:di], 0x0F20

    POP es

    CALL update_cursor
.L10:
    RET

get_key:
    XOR ah, ah
    INT 0x16
    RET

error: ; error
    ; input: none
    ; output: none
    ; clobbers: si
    MOV si, error_msg
    CALL print_string
    RET


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
    MOV cx, CHARS_PER_LINE * 24
    REP MOVSW

    ; clear last line
    MOV ax, 0x0F20
    MOV di, CHARS_PER_LINE * 2 * 24
    MOV cx, CHARS_PER_LINE
    REP STOSW

    ; restore kernel data segment
    POP ds

    ; move cursor to start of last line
    MOV di, CHARS_PER_LINE * 2 * 24
    MOV WORD [VGA_cursor], di

    CALL update_cursor

    POP es
    POP si
    RET

update_cursor:
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

strcmp: ; compare strings. 
    ; inputs: si = ptr to string 1 in DS, di = ptr to string 2 in DS
    ; outputs: ax = 0 if equal, ax = 1 if not
    PUSH si
    PUSH di
    PUSH bx
.L12:
    ; set al & bl to characters @ si & di
    MOV al, [si]
    MOV bl, [di]

    ; check if equal
    CMP al, bl
    JNE .L13

    ; if finished, then both al & bl would be null
    TEST al, al
    JZ .L14

    ; increment si, di and try again
    INC si
    INC di
    JMP .L12
.L13: ; unequal
    ; set unequal result
    MOV ax, 1

    POP bx
    POP di
    POP si
    RET
.L14: ; equal
    ; set equal result
    XOR ax, ax

    POP bx
    POP di
    POP si
    RET

strupr:
    ; inputs: si = ptr to string
    ; outputs: none
    ; clobber: al
    PUSH ax
    PUSH si
.L25:
    MOV al, [si]
    TEST al, al
    JZ .L21

    CMP al, 'a'
    JB .L22

    CMP al, 'z'
    JA .L22

    SUB al, 32 ; convert to uppercase
.L22: ; replace the character
    MOV [si], al ; write back
    INC si
    JMP .L25
.L21: ; finished
    POP si
    POP ax
    RET

strlwr: ; modify a string to have all letters lowercase
    ; inputs: si = ptr to string
    ; outputs: none
    ; clobber: al
    PUSH ax
    PUSH si
.L35:
    MOV al, [si]

    CMP al, 0
    JE .L19

    CMP al, 'A'
    JB .L20

    CMP al, 'Z'
    JA .L20

    ADD al, 32 ; convert to lowercase
.L20:
    MOV [si], al ; write back
    INC si
    JMP .L35
.L19: ; finished
    POP si
    POP ax
    RET

putchar:
    CALL print_char
    RET

puts:
    CALL print_string
    CALL newline
    RET

load_AOSfs_file: ; load file and store in the range of 0x80000-0x8FFFF
    ; inputs: si = ptr to filename, di = ptr to extension
    ; outputs: ax = 0 if fail, ax = 1 if success
    ; clobbers: ax, bx, cx, dx, di

    PUSH es ; preserve es
    PUSH di
    PUSH si
    PUSH ds

    ; STEP 1: load the header into low data (0x1000-0x11FF)
    MOV ax, 0x0100
    MOV es, ax
    XOR bx, bx

    MOV ah, 0x02 ; read sectors
    MOV al, 1 ; read 1 sector
    XOR dl, dl ; from the floppy
    ; load from sector 1 = C0H0S2
    XOR ch, ch
    XOR dh, dh
    MOV cl, 2

    INT 0x13
    JC .L27

    ; compare signature
    MOV ax, WORD [es:0]
    CMP ax, 'AO'
    JNE .L27

    MOV ax, WORD [es:2]
    CMP ax, 'SF'
    JNE .L27

    MOV ax, WORD [es:6]
    MOV WORD [file_table_start], ax
    MOV ax, WORD [es:8]
    MOV WORD [file_table_sectors], ax
    MOV ax, WORD [es:10]
    MOV WORD [data_start], ax

    ; STEP 2: load the file table into low data segment (0x1200-0x2FFF)
    MOV ax, 0x0120
    MOV es, ax
    XOR bx, bx

    ; set up registers for INT 0x13
    MOV ah, 0x02 ; request: read sectors
    MOV al, BYTE [file_table_sectors]
    XOR dl, dl ; from the floppy
    ; load from sector 2 - C0H0S3 in CHS
    XOR ch, ch ; cylinder
    XOR dh, dh ; head
    MOV cl, BYTE [file_table_start] ; sector
    INC cl

    INT 0x13

    JC .L27 ; if carry flag set, then error

    MOV cx, TOTAL_FILE_ENTRIES
    XOR bx, bx ; bx = offset in file table
.L15: 
    ; STEP 3: check if file exists
    ; compare filename to entry
    ; MOV si, si - si already points to filename, so no need to set
    LEA di, [bx + FILE_EXT_OFFSET] ; ptr to file extension
    CALL strcmp

    CMP ax, 1
    JE .L26 ; if strings equal load the file

    MOV si, di ; swap si to be the extension
    LEA di, [bx + FILE_EXT_OFFSET]
    CALL strcmp

    CMP ax, 1
    JE .L16
.L26: ; next loop
    POP di
    POP si

    ADD bx, FILE_ENTRY_SIZE ; move to next file entry
    LOOP .L15

    MOV ax, 0
    JMP .L17
.L16: ; if file name & target are equal, load the file
    POP di
    POP si

    ; STEP 4: load file into memory

    ; check if file is big
    MOV ax, [bx + FILE_SIZE_OFFSET] ; offset of byte size
    CMP ax, 0
    JNE .L18

    MOV ax, [bx + FILE_START_SECTOR_OFFSET] ; starting sector as an LBA to prepare for division
    ; sector = (LBA % 18) + 1
    PUSH bx

    XOR dx, dx
    MOV bx, 18
    DIV bx

    MOV cl, dl
    INC cl

    ; ax = temp
    ; head & cylinder

    XOR dx, dx
    MOV cx, 2
    DIV cx

    MOV dh, dl
    MOV ch, al
    ; set destination buffer
    MOV ax, FILE_BUFFER
    MOV es, ax
    XOR bx, bx
    ; prepare for INT 0x13
    MOV ah, 2 ; request: read sectors
    MOV al, BYTE [bx + FILE_SECTORS_OFFSET] ; sectors to read

    ; cl, ch, dh are already CHS values
    XOR dl, dl ; from the floppy

    INT 0x13
    JC .L27

    POP bx

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
.L27: ; disk read fail
    MOV si, disk_fail_msg
    CALL print_string
    JMP .L17

; DATA
; strings
kernel_boot_msg: db "Kernel load done - ready.", 10, 0
; test string with newline and carriage return
error_msg: db "Error, shutdown.", 0
test_file_name: db "test", 0
test_file_ext: db "txt", 0
file_too_big_msg: db "DAMN! Are you writing a novel?!", 0

help_msg: 
    db "Here are the commands you can use:", 10
    db "* HELP  - displays this message", 10
    db "* CLEAR - clears the screen", 10, 
    db "* ECHO  - print text to the screen", 10, 0

invalid_command_msg: db "Invalid command; type HELP to see the commands you can use.", 10, 0
disk_fail_msg: db "Disk read failure.", 0

; file system vars
file_table_start: dw 0
file_table_sectors: dw 0
data_start: dw 0

; commands
command_HELP: db "HELP", 0

; aliases of CLEAR
command_CLEAR: db "CLEAR", 0
command_CLS: db "CLS", 0

command_ECHO: db "ECHO", 0

; aliases of VERSION
command_VER: db "VER", 0
command_VERSION: db "VERSION", 0

; command prompt data
input_buffer: times 33 db 0 ; 33 chars + end null
input_len: db 0

argc: db 0
argv: times 16 dw 0 ; 16 args, store the addresses of each arg here

; other data
VGA_cursor: dw 0

; CONSTANTS

; keys
BACKSPACE: equ 0x08
NEWLINE: equ 0x0A
CR: equ 0x0D

; memory addresses
FILE_BUFFER: equ 0x8000
STACK_SEG: equ 0x9000
VGA_MEM_START: equ 0xB800

; file system constants
FILE_NAME_OFFSET: equ 0
FILE_EXT_OFFSET: equ 16
FILE_START_SECTOR_OFFSET: equ 21
FILE_SECTORS_OFFSET: equ 23
FILE_SIZE_OFFSET: equ 28

FILE_ENTRY_SIZE: equ 32
TOTAL_FILE_ENTRIES: equ 240

; command constants
MAX_BUFFER_LEN: equ 32

; VGA data
CHARS_PER_LINE: equ 80