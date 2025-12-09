"""Tests that the installer image builds a bootable FAT32 ESP."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

import pytest

from pyfatfs import PyFat, PyFatFS

REPO_ROOT = Path(__file__).resolve().parents[2]
BOOT_OFFSET = 1 * 1024 * 1024


def _stage_dist_file(path: Path, contents: bytes) -> Path | None:
    path.parent.mkdir(parents=True, exist_ok=True)
    backup = None
    if path.exists():
        backup = path.with_suffix(path.suffix + ".bak-test")
        if backup.exists():
            backup.unlink()
        path.rename(backup)
    path.write_bytes(contents)
    return backup


def _restore_dist_file(path: Path, backup: Path | None) -> None:
    if backup is not None and backup.exists():
        if path.exists():
            path.unlink()
        backup.rename(path)
    elif path.exists():
        path.unlink()


def test_installer_image_esp_is_fat32(tmp_path: Path) -> None:
    kernel_path = REPO_ROOT / "dist" / "vmlinuz-installer"
    initrd_path = REPO_ROOT / "dist" / "initrd-installer.img"
    kernel_backup: Path | None = None
    initrd_backup: Path | None = None
    try:
        kernel_backup = _stage_dist_file(kernel_path, b"kernel")
        initrd_backup = _stage_dist_file(initrd_path, b"initrd")
        env = os.environ.copy()

        env = os.environ.copy()
        env["SP_IMG_OUT"] = str(tmp_path / "installer.img")
        env["SP_IMG_SIZE"] = "32M"
        env["SP_IMG_BOOT_SIZE_MB"] = "12"
        env["SP_IMG_CONFIG_SIZE_MB"] = "12"
        stub_efi = tmp_path / "grubx64.efi"
        stub_efi.write_bytes(b"EFI-STUB")
        env["SP_GRUB_EFI_BIN"] = str(stub_efi)

        loop_probe: subprocess.CompletedProcess[str] = subprocess.run(
            ["sudo", "-E", "losetup", "--find", "--show", "/dev/null"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if loop_probe.returncode != 0:
            pytest.skip(
                "losetup unavailable; skipping installer media bootability smoke test"
            )
        loop_device = loop_probe.stdout.strip()
        subprocess.run(["sudo", "-E", "losetup", "-d", loop_device], check=True)
        subprocess.run(
            ["sudo", "-E", "/bin/sh", "tools/make_installer_img.sh"],
            cwd=str(REPO_ROOT),
            env=env,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        image_path = Path(env["SP_IMG_OUT"])
        assert image_path.exists(), "Installer image was not created"

        with PyFatFS(str(image_path), offset=BOOT_OFFSET) as fat_fs:
            assert fat_fs.fs.fat_type == PyFat.FAT_TYPE_FAT32
            assert fat_fs.exists("EFI/BOOT/BOOTX64.EFI")
            assert fat_fs.exists("EFI/BOOT/grub.cfg")
            assert fat_fs.exists("boot/vmlinuz-installer")
            assert fat_fs.exists("boot/initrd-installer.img")

            with fat_fs.openbin("EFI/BOOT/grub.cfg") as grub_cfg:
                grub_contents = grub_cfg.read().decode()

        assert "vmlinuz-installer" in grub_contents
        assert "initrd-installer.img" in grub_contents
    finally:
        _restore_dist_file(kernel_path, kernel_backup)
        _restore_dist_file(initrd_path, initrd_backup)
