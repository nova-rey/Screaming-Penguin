from pathlib import Path

import pytest

from tests.installer.test_installer_initrd import (
    HAS_REQUIRED_TOOLS,
    _prepare_kernel_environment,
    _run_installer_initrd_build,
)


@pytest.mark.skipif(
    not HAS_REQUIRED_TOOLS,
    reason="gzip/cpio required for initrd validation",
)
def test_installer_initrd_populates_disk_by_label() -> None:
    env = _prepare_kernel_environment()
    initrd_path = _run_installer_initramfs_build(env)

    assert initrd_path.exists(), "initrd-installer.img should exist after the build"

    init_script_path = Path("build/installer-initramfs/init")
    init_content = init_script_path.read_text(encoding="utf-8")

    assert "sp_populate_disk_by_label" in init_content
    assert "blkid -o export" in init_content
    assert "mkdir -p /dev/disk/by-label" in init_content
