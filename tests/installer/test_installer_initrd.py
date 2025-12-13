import shutil
import subprocess
from pathlib import Path
from shlex import quote

import pytest

MIN_INITRD_SIZE_BYTES = 1 * 1024 * 1024
REQUIRED_TOOLS = ("gzip", "cpio")
HAS_REQUIRED_TOOLS = all(shutil.which(tool) for tool in REQUIRED_TOOLS)

RUNTIME_LIB_ENTRIES = (
    "init",
    "runtime/lib/rescue_mode.sh",
    "runtime/lib/disk_layout.sh",
    "runtime/lib/disk_execute.sh",
    "runtime/lib/rootfs_deploy.sh",
    "runtime/lib/bootloader.sh",
    "runtime/lib/config_discovery.sh",
)


@pytest.mark.skipif(
    not HAS_REQUIRED_TOOLS,
    reason="gzip/cpio required for initrd validation",
)
def test_installer_initrd_contains_runtime_payload() -> None:
    subprocess.run(
        ["bash", "tools/build_installer_initramfs.sh"],
        check=True,
    )

    initrd_path = Path("dist") / "initrd-installer.img"
    assert initrd_path.exists(), "initrd-installer.img should exist after the build"

    assert (
        initrd_path.stat().st_size >= MIN_INITRD_SIZE_BYTES
    ), f"initrd-installer.img is too small ({initrd_path.stat().st_size} bytes)"

    list_cmd = f"gzip -cd {quote(str(initrd_path))} | cpio -t -H newc"
    proc = subprocess.run(
        ["bash", "-lc", list_cmd],
        check=True,
        capture_output=True,
        text=True,
    )

    entries = {
        line.strip().lstrip("./") for line in proc.stdout.splitlines() if line.strip()
    }

    assert "bin/busybox" in entries
    for required in RUNTIME_LIB_ENTRIES:
        assert required in entries
