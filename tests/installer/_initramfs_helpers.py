from pathlib import Path

TEST_KERNEL_VERSION = "test-kernel"
FAT_MODULE_PATHS = (
    Path("kernel/fs/fat/fat.ko"),
    Path("kernel/fs/fat/vfat.ko"),
    Path("kernel/fs/nls/nls_cp437.ko"),
    Path("kernel/fs/nls/nls_iso8859-1.ko"),
)
