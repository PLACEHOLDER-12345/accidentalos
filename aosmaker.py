BOOT_SECTOR_SIZE = 512
FLOPPY_SIZE = 1474560  # 1.44 MB

BOOT_PATH = r"boot.bin"
DEFAULT_HEADER_PATH = r"defaultheader.bin"
DEFAULT_FILE_TABLE_PATH = r"defaultfiletable.bin"
KERNEL_PATH = r"kernel.bin"
IMG_PATH    = r"accidentalos.img"
LOREM_IPSUM_TEST_PATH = r"test.bin"

with open(BOOT_PATH, "rb") as b:
    boot_sector = b.read()

with open(KERNEL_PATH, "rb") as k:
    kernel = k.read()

with open(DEFAULT_HEADER_PATH, "rb") as h:
    default_header = h.read()

with open(DEFAULT_FILE_TABLE_PATH, "rb") as t:
    default_file_table = t.read()

with open(LOREM_IPSUM_TEST_PATH, "rb") as l:
    lorem_ipsum_test = l.read()

if len(boot_sector) != BOOT_SECTOR_SIZE:
    raise ValueError(f"Boot sector must be exactly 512 bytes (got {len(boot_sector)})")

with open(IMG_PATH, "wb") as f:
    f.write(boot_sector)
    f.write(default_header)
    f.write(default_file_table)
    f.seek(25 * 512) # move to sector 17 (0-based)
    f.write(kernel)
    f.seek(29 * 512) # move to sector 21
    f.write(lorem_ipsum_test)
    remaining = FLOPPY_SIZE - f.tell()
    if remaining > 0:
        f.write(b"\x00" * remaining)

print("accidentalos.img created successfully")