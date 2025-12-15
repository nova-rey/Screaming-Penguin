import os
import shutil
import subprocess
from pathlib import Path
from shlex import quote

import pytest

REQUIRED_TOOLS = ("bash", "gzip", "cpio", "strings")
HAS_REQUIRED_TOOLS = all(shutil.which(tool) for tool in REQUIRED_TOOLS)
INITRD_PATH = Path("dist") / "initrd-installer.img"


@pytest.fixture(autouse=True)
def clean_initrd():
    if INITRD_PATH.exists():
        INITRD_PATH.unlink()
    yield

def _run_build(env) -> None:
    subprocess.run(
        ["bash", "tools/build_installer_initramfs.sh"],
        check=True,
        env=env,
    )


@pytest.mark.skipif(
    not HAS_REQUIRED_TOOLS,
    reason="bash/gzip/cpio/strings required for initrd validation",
)
def test_installer_initrd_includes_kernel_matched_modules(tmp_path: Path) -> None:
    kernel_version = "99.88.77-fake"
    kernel_file = tmp_path / "vmlinuz-installer"
    kernel_file.write_text("Linux version 99.88.77-fake (test) #1\n")

    modules_src = tmp_path / "modules" / kernel_version
    modules_src.mkdir(parents=True)
    (modules_src / "dummy.ko").write_text("fake kernel module")

    env = os.environ.copy()
    env.update(
        {
            "SP_INSTALLER_KERNEL_PATH": str(kernel_file),
            "SP_INSTALLER_MODULES_SRC": str(modules_src),
        }
    )

    _run_build(env)

    assert INITRD_PATH.exists(), "initrd-installer.img should exist after build"

    extracted = tmp_path / "initrd-root"
    extracted.mkdir()
    extract_cmd = (
        "set -euo pipefail; "
        f"gzip -cd {quote(str(INITRD_PATH))} | "
        f"(cd {quote(str(extracted))} && cpio -id)"
    )
    subprocess.run(["bash", "-c", extract_cmd], check=True)

    modules_root = extracted / "lib" / "modules"
    assert modules_root.is_dir(), "/lib/modules should be present in the initrd"

    version_dirs = [entry for entry in modules_root.iterdir() if entry.is_dir()]
    assert version_dirs, "Expected at least one modules directory"
    assert len(version_dirs) == 1, "Only the installer kernel's modules should be staged"
    assert version_dirs[0].name == kernel_version
    assert (version_dirs[0] / "dummy.ko").exists()


@pytest.mark.skipif(
    not HAS_REQUIRED_TOOLS,
    reason="bash/gzip/cpio/strings required for initrd validation",
)
def test_build_installer_initramfs_fails_when_modules_mismatched(tmp_path: Path) -> None:
    kernel_file = tmp_path / "vmlinuz-installer"
    kernel_file.write_text("Linux version mismatch-kernel (test) #1\n")

    env = os.environ.copy()
    env["SP_INSTALLER_KERNEL_PATH"] = str(kernel_file)

    with pytest.raises(subprocess.CalledProcessError) as excinfo:
        subprocess.run(
            ["bash", "tools/build_installer_initramfs.sh"],
            check=True,
            env=env,
            capture_output=True,
        )

    stderr = excinfo.value.stderr.decode("utf-8", "ignore")
    assert "Kernel modules directory missing" in stderr
