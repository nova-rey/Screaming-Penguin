from __future__ import annotations

import os
import shutil
import shlex
import subprocess
import tempfile
from pathlib import Path

import pytest

from tests.installer._initramfs_helpers import FAT_MODULE_PATHS, TEST_KERNEL_VERSION

REPO_ROOT = Path(__file__).resolve().parents[2]


def _prepare_kernel_environment(kernel_version: str = TEST_KERNEL_VERSION) -> dict[str, str]:
    """Create the stub kernel and modules that installer initramfs tests rely on."""
    kernel_dir = REPO_ROOT / "build" / "runtime"
    kernel_dir.mkdir(parents=True, exist_ok=True)
    kernel_image = kernel_dir / "vmlinuz"
    kernel_image.write_bytes(b"FAKE-KERNEL")

    modules_root = REPO_ROOT / "build" / "runtime-chroot" / "lib" / "modules"
    modules_root.mkdir(parents=True, exist_ok=True)
    modules_src = modules_root / kernel_version
    if modules_src.exists():
        shutil.rmtree(modules_src)
    modules_src.mkdir(parents=True, exist_ok=True)
    (modules_src / "dummy").write_text("module")

    for module_path in FAT_MODULE_PATHS:
        target_path = modules_src / module_path
        target_path.parent.mkdir(parents=True, exist_ok=True)
        target_path.write_text(f"stub {module_path.name}")

    env = os.environ.copy()
    env.update(
        {
            "SP_INSTALLER_KERNEL_IMAGE": str(kernel_image),
            "SP_INSTALLER_KERNEL_VERSION": kernel_version,
            "SP_INSTALLER_MODULES_ROOT": str(modules_root),
        }
    )

    return env


def _run_installer_initramfs_build(env: dict[str, str]) -> Path:
    """Run tools/build_installer_initramfs.sh and return the output initrd path."""
    try:
        subprocess.run(
            ["bash", "tools/build_installer_initramfs.sh"],
            cwd=str(REPO_ROOT),
            check=True,
            capture_output=True,
            text=True,
            env=env,
        )
    except subprocess.CalledProcessError as exc:
        stdout = exc.stdout.rstrip("\n") if exc.stdout else "<no stdout>"
        stderr = exc.stderr.rstrip("\n") if exc.stderr else "<no stderr>"
        pytest.fail(
            "tools/build_installer_initramfs.sh failed "
            f"(exit {exc.returncode}).\nstdout:\n{stdout}\nstderr:\n{stderr}"
        )

    return REPO_ROOT / "dist" / "initrd-installer.img"


def _list_initrd_entries(initrd_path: Path) -> list[str]:
    """Return a sorted list of file names inside the installer initrd."""
    cmd = f"gzip -cd {shlex.quote(str(initrd_path))} | cpio -t -H newc"
    cp = subprocess.run(
        ["bash", "-c", cmd],
        cwd=str(REPO_ROOT),
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    entries = [line.strip().lstrip("./") for line in cp.stdout.splitlines() if line.strip()]
    entries.sort()
    return entries


def _read_initrd_file(initrd_path: Path, file_path: str) -> str:
    """Extract a single file from the initrd and return its contents."""
    quoted_file_path = shlex.quote(file_path)
    cmd = (
        "set -euo pipefail; "
        f"gzip -dc {shlex.quote(str(initrd_path))} | cpio -i --quiet {quoted_file_path} -d >/dev/null; "
        f"cat {quoted_file_path}"
    )
    with tempfile.TemporaryDirectory() as extract_dir:
        cp = subprocess.run(
            ["bash", "-c", cmd],
            cwd=extract_dir,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    return cp.stdout
