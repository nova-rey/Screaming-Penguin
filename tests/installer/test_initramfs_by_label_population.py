import pytest

from tests.installer.initrd_test_helpers import (
    _list_initrd_entries,
    _prepare_kernel_environment,
    _read_initrd_file,
    _run_installer_initramfs_build,
)
from tests.installer.test_installer_initrd import HAS_REQUIRED_TOOLS


@pytest.mark.skipif(
    not HAS_REQUIRED_TOOLS,
    reason="gzip/cpio required for initrd validation",
)
def test_installer_initrd_populates_disk_by_label() -> None:
    env = _prepare_kernel_environment()
    initrd_path = _run_installer_initramfs_build(env)

    assert initrd_path.exists(), "initrd-installer.img should exist after the build"

    entries = _list_initrd_entries(initrd_path)
    assert "init" in entries

    init_content = _read_initrd_file(initrd_path, "init")

    assert "sp_populate_disk_by_label" in init_content
    assert "blkid -o export" in init_content
    assert "mkdir -p /dev/disk/by-label" in init_content
