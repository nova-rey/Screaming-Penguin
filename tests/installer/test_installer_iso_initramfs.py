import shutil
import subprocess
from pathlib import Path
from shlex import quote

import pytest

REQUIRED_TOOLS = ("xorriso", "cpio", "zcat")
HAS_REQUIRED_TOOLS = all(shutil.which(tool) for tool in REQUIRED_TOOLS)


@pytest.mark.skipif(
    not HAS_REQUIRED_TOOLS,
    reason="xorriso/cpio/zcat required for ISO initramfs test",
)
def test_installer_iso_contains_busybox(tmp_path: Path) -> None:
    iso = Path("dist/screaming-penguin.iso")
    if not iso.exists():
        pytest.skip(
            "dist/screaming-penguin.iso not present; run make iso/dist-release first"
        )

    initrd_path = tmp_path / "initrd-installer.img"
    subprocess.run(
        [
            "xorriso",
            "-osirrox",
            "on",
            "-indev",
            str(iso),
            "-extract",
            "/boot/initrd-installer.img",
            str(initrd_path),
        ],
        check=True,
    )

    initrd_list_cmd = f"zcat {quote(str(initrd_path))} | cpio -t -H newc"
    proc = subprocess.run(
        ["bash", "-lc", initrd_list_cmd],
        check=True,
        capture_output=True,
        text=True,
    )

    entries = {line.strip() for line in proc.stdout.splitlines() if line.strip()}
    assert "init" in entries
    assert "bin/busybox" in entries
