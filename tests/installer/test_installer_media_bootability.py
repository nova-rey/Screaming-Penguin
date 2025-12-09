"""Tests that the installer image builds a bootable FAT32 ESP."""

from __future__ import annotations

import filecmp
import os
import shutil
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
            ["sudo", "-E", "/bin/bash", "tools/make_installer_img.sh"],
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
        runtime_kernel = REPO_ROOT / "build" / "runtime" / "vmlinuz"
        assert runtime_kernel.exists(), (
            "build/runtime/vmlinuz should still exist after make_installer_img.sh; "
            "the img build must not delete the shared runtime artifacts."
        )
    finally:
        _restore_dist_file(kernel_path, kernel_backup)
        _restore_dist_file(initrd_path, initrd_backup)


def test_make_installer_iso_falls_back_to_dist_artifacts(tmp_path: Path) -> None:
    for tool in ("xorriso", "grub-mkstandalone"):
        if shutil.which(tool) is None:
            pytest.skip(f"{tool} unavailable; skipping ISO fallback test")

    dist_kernel = REPO_ROOT / "dist" / "vmlinuz-installer"
    dist_initrd = REPO_ROOT / "dist" / "initrd-installer.img"
    dist_kernel_backup: Path | None = None
    dist_initrd_backup: Path | None = None
    runtime_kernel = REPO_ROOT / "build" / "runtime" / "vmlinuz"
    runtime_initrd = REPO_ROOT / "build" / "runtime" / "initrd.img"
    runtime_kernel_backup: Path | None = None
    runtime_initrd_backup: Path | None = None
    iso_output = REPO_ROOT / "dist" / "screaming-penguin.iso"
    stub_efi = tmp_path / "grubx64.efi"
    stub_efi.write_bytes(b"EFI-STUB")
    env = os.environ.copy()
    env["SP_GRUB_EFI_BIN"] = str(stub_efi)

    try:
        dist_kernel_backup = _stage_dist_file(dist_kernel, b"kernel")
        dist_initrd_backup = _stage_dist_file(dist_initrd, b"initrd")

        if runtime_kernel.exists():
            kernel_backup_path = runtime_kernel.with_suffix(
                runtime_kernel.suffix + ".bak-test"
            )
            if kernel_backup_path.exists():
                kernel_backup_path.unlink()
            runtime_kernel.rename(kernel_backup_path)
            runtime_kernel_backup = kernel_backup_path

        if runtime_initrd.exists():
            initrd_backup_path = runtime_initrd.with_suffix(
                runtime_initrd.suffix + ".bak-test"
            )
            if initrd_backup_path.exists():
                initrd_backup_path.unlink()
            runtime_initrd.rename(initrd_backup_path)
            runtime_initrd_backup = initrd_backup_path

        if iso_output.exists():
            iso_output.unlink()

        subprocess.run(
            ["/bin/bash", "tools/make_installer_iso.sh"],
            cwd=str(REPO_ROOT),
            env=env,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        assert iso_output.exists()
    finally:
        _restore_dist_file(dist_kernel, dist_kernel_backup)
        _restore_dist_file(dist_initrd, dist_initrd_backup)

        if runtime_kernel_backup is not None and runtime_kernel_backup.exists():
            if runtime_kernel.exists():
                runtime_kernel.unlink()
            runtime_kernel_backup.rename(runtime_kernel)
        elif runtime_kernel.exists() and runtime_kernel_backup is None:
            runtime_kernel.unlink()

        if runtime_initrd_backup is not None and runtime_initrd_backup.exists():
            if runtime_initrd.exists():
                runtime_initrd.unlink()
            runtime_initrd_backup.rename(runtime_initrd)
        elif runtime_initrd.exists() and runtime_initrd_backup is None:
            runtime_initrd.unlink()

        if iso_output.exists():
            iso_output.unlink()


def test_iso_initrd_matches_dist_installer_initrd(tmp_path: Path) -> None:
    if shutil.which("xorriso") is None:
        pytest.skip("xorriso unavailable; skipping ISO initrd identity test")

    dist_dir = REPO_ROOT / "dist"
    dist_initrd = dist_dir / "initrd-installer.img"
    iso_output = dist_dir / "screaming-penguin.iso"
    stub_efi = tmp_path / "grubx64.efi"
    stub_efi.write_bytes(b"EFI-STUB")
    env = os.environ.copy()
    env["SP_GRUB_EFI_BIN"] = str(stub_efi)

    if iso_output.exists():
        iso_output.unlink()

    subprocess.run(
        ["/bin/bash", "tools/build_installer_initramfs.sh"],
        cwd=str(REPO_ROOT),
        env=env,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    subprocess.run(
        ["/bin/bash", "tools/make_installer_iso.sh"],
        cwd=str(REPO_ROOT),
        env=env,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    assert iso_output.exists(), "ISO build failed to produce screaming-penguin.iso"

    extracted_initrd = tmp_path / "initrd-installer.iso.img"
    subprocess.run(
        [
            "xorriso",
            "-osirrox",
            "on",
            "-indev",
            str(iso_output),
            "-extract",
            "/boot/initrd-installer.img",
            str(extracted_initrd),
        ],
        check=True,
    )

    assert filecmp.cmp(
        str(dist_initrd),
        str(extracted_initrd),
        shallow=False,
    ), "ISO initrd image differs from dist/initrd-installer.img"
