from pathlib import Path
import re

import pytest

from tests.installer.initrd_test_helpers import (
    _prepare_kernel_environment,
    _run_installer_initramfs_build,
)
from tests.installer.test_installer_initrd import HAS_REQUIRED_TOOLS


@pytest.mark.skipif(
    not HAS_REQUIRED_TOOLS,
    reason="gzip/cpio required for initrd validation",
)
def test_installer_initrd_populates_by_label_namespace() -> None:
    env = _prepare_kernel_environment()
    initrd_path = _run_installer_initramfs_build(env)

    assert initrd_path.exists(), "initrd-installer.img should exist after the build"

    init_script_path = Path("build/installer-initramfs/init")
    init_content = init_script_path.read_text(encoding="utf-8")

    assert "sp_populate_by_label_namespace" in init_content
    assert "sp_link_label_if_valid" in init_content
    pattern = r'("?(\$blkid_bin|blkid)"?)\s+-o\s+export\b'
    assert re.search(pattern, init_content), init_content
    assert 'ln -sf -- "$devname" "${label_dir}/${safe_label}"' in init_content
    assert (
        '[SP-INSTALLER][WARN] no labeled block devices found via blkid; by-label namespace will be empty'
        in init_content
    )
