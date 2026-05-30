AOS memory map for real mode:

00000-004FF: system memory
00500-00FFF: scratch
01000-07BFF: kernel data
    * 01000-011FF: file header buffer for load_file
    * 01200-02FFF: file table buffer for load_file
    * 03000-07BFF: other kernel data
07C00-07DFF: boot
07E00-07FFF: unused
08000-1FFFF: kernel code and data
20000-7BFFF: user programs (code and data)
80000-8FFFF: file loading buffer
90000-9FFFF: stack
A0000-BFFFF: VGA memory
C0000-FFFFF: reserved