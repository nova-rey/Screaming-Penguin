"""Tests covering the installer kernel/modules identity contract."""

from __future__ import annotations

import os
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
DIST_INITRD = REPO_ROOT / "dist" / "initrd-installer.img"
REQUIRED_TOOLS = ("gzip", "cpio")
HAS_REQUIRED_TOOLS = all(shutil.which(tool) for tool in REQUIRED_TOOLS)


def _stage_dist_file(path: Path) -> Path | None:
    path.parent.mkdir(parents=True, exist_ok=True)
    backup = None
    if path.exists():
        backup = path.with_suffix(path.suffix + ".bak-test")
        if backup.exists():
            backup.unlink()
        path.rename(backup)
    return backup


def _restore_dist_file(path: Path, backup: Path | None) -> None:
    if backup is not None and backup.exists():
        if path.exists():
            path.unlink()
        backup.rename(path)
    elif path.exists():
        path.unlink()


def _list_initrd_entries(initrd_path: Path) -> set[str]:
    cmd = f"gzip -cd {shlex.quote(str(initrd_path))} | cpio -t -H newc"
    proc = subprocess.run(
        ["bash", "-lc", cmd],
        check=True,
        capture_output=True,
        text=True,
        cwd=str(REPO_ROOT),
    )
    return {
        line.strip().lstrip("./")
        for line in proc.stdout.splitlines()
        if line.strip()
    }


def _write_stub_kernel(kernel_path: Path, version: str) -> None:
    kernel_path.write_bytes(
        f"Linux version {version} (stub)\nDummy kernel for {version}\n".encode("ascii"),
        )


@pytest.mark.skipif(
    not HAS_REQUIRED_TOOLS,
    reason="gzip/cpio required for initrd inspection",
)
def test_initrd_contains_matching_modules(tmp_path: Path) -> None:
    kernel_version = "6.1.0-test-kernel"
    kernel_image = tmp_path / "vmlinuz-installer"
    _write_stub_kernel(kernel_image, kernel_version)

    modules_root = tmp_path / "modules"
    (modules_root / kernel_version).mkdir(parents=True)
    module_file = modules_root / kernel_version / "dummy.ko"
    module_file.write_bytes(b"module-data")

    env = os.environ.copy()
    env.update(
        {
            "SP_INSTALLER_KERNEL_IMAGE": str(kernel_image),
            "SP_INSTALLER_MODULES_ROOT": str(modules_root),
            "SP_LOG_DEVICE": str(tmp_path / "installer.log"),
        }
    )

    initrd_backup = _stage_dist_file(DIST_INITRD)
    try:
        subprocess.run(
            ["bash", "tools/build_installer_initramfs.sh"],
            cwd=str(REPO_ROOT),
            env=env,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        entries = _list_initrd_entries(DIST_INITRD)
        assert (
            f"lib/modules/{kernel_version}/dummy.ko" in entries
        ), "Initrd should contain the kernel-matched module"
    finally:
        _restore_dist_file(DIST_INITRD, initrd_backup)


def test_build_initrd_fails_without_matching_modules(tmp_path: Path) -> None:
    kernel_version = "6.1.0-missing"
    kernel_image = tmp_path / "vmlinuz-installer"
    _write_stub_kernel(kernel_image, kernel_version)
    modules_root = tmp_path / "modules"

    env = os.environ.copy()
    env.update(
        {
            "SP_INSTALLER_KERNEL_IMAGE": str(kernel_image),
            "SP_INSTALLER_MODULES_ROOT": str(modules_root),
            "SP_LOG_DEVICE": str(tmp_path / "installer.log"),
        }
    )

    result = subprocess.run(
        ["bash", "tools/build_installer_initramfs.sh"],
        cwd=str(REPO_ROOT),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode != 0
    assert "Kernel modules directory missing" in result.stderr


def test_init_script_fails_when_expected_modules_missing(tmp_path: Path) -> None:
    log_path = tmp_path / "init.log"
    env = os.environ.copy()
    env.update(
        {
            "SP_EXPECTED_KERNEL_VERSION": "missing-runtime-version",
            "SP_LOG_DEVICE": str(log_path),
        }
    )

    cmd = "\n".join(
        [
            "set -euo pipefail",
            "SP_SKIP_INIT_MAIN=1 . installer/init/init.sh",
            "sp_validate_kernel_modules",
        ]
    )

    result = subprocess.run(
        ["bash", "-c", cmd],
        cwd=str(REPO_ROOT),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    assert result.returncode != 0
    assert "[SP-INSTALLER] FATAL kernel/modules mismatch" in result.stderr
