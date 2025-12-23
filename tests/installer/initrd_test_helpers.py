from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from shlex import quote

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]


TEST_KERNEL_VERSION = "test-kernel"
FAT_MODULE_PATHS = (
    Path("kernel/fs/fat/fat.ko"),
    Path("kernel/fs/fat/vfat.ko"),
    Path("kernel/fs/nls/nls_cp437.ko"),
    Path("kernel/fs/nls/nls_iso8859-1.ko"),
)


def _prepare_kernel_environment(kernel_version: str = TEST_KERNEL_VERSION) -> dict[str, str]:
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
    try:
        subprocess.run(
            ["bash", "tools/build_installer_initramfs.sh"],
            check=True,
            capture_output=True,
            text=True,
            env=env,
            cwd=str(REPO_ROOT),
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
    quoted_initrd = quote(str(initrd_path))
    list_cmd = f"gzip -cd {quoted_initrd} | cpio -t -H newc"
    proc = subprocess.run(
        ["bash", "-lc", list_cmd],
        check=True,
        capture_output=True,
        text=True,
        cwd=str(REPO_ROOT),
    )

    entries = [
        line.strip().lstrip("./")
        for line in proc.stdout.splitlines()
        if line.strip()
    ]
    entries.sort()
    return entries


def _read_initrd_file(initrd_path: Path, file_path: str) -> str:
    quoted_initrd = quote(str(initrd_path))
    quoted_file = quote(file_path)
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)
        cmd = (
            f"set -euo pipefail; "
            f"cd {quote(str(temp_path))}; "
            f"gzip -dc {quoted_initrd} | cpio -i --quiet {quoted_file} -d >/dev/null; "
            f"cat {quoted_file}"
        )
        cp = subprocess.run(
            ["bash", "-lc", cmd],
            cwd=str(REPO_ROOT),
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        return cp.stdout
