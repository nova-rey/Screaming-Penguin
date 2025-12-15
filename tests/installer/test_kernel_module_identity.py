"""Tests covering the installer kernel/modules identity contract."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def _write_stub_kernel(path: Path, version: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"Linux version {version}\n", encoding="ascii")


def _run_detection(env_overrides: dict[str, str]) -> subprocess.CompletedProcess:
    env = os.environ.copy()
    env.update(env_overrides)
    env.setdefault("SP_INSTALLER_KERNEL_DETECT_MODE", "1")
    return subprocess.run(
        ["bash", "tools/build_installer_initramfs.sh"],
        cwd=str(REPO_ROOT),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def test_detection_prefers_override(tmp_path: Path) -> None:
    kernel_version = "7.1.0-override"
    kernel_image = tmp_path / "vmlinuz-installer"
    _write_stub_kernel(kernel_image, kernel_version)

    modules_root = tmp_path / "modules"
    modules_src = modules_root / kernel_version

    result = _run_detection(
        {
            "SP_INSTALLER_KERNEL_IMAGE": str(kernel_image),
            "SP_INSTALLER_KERNEL_VERSION": kernel_version,
            "SP_INSTALLER_MODULES_ROOT": str(modules_root),
        }
    )

    assert result.returncode == 0
    assert "Kernel version detection method: override" in result.stdout
    assert f"Installer kernel version: {kernel_version}" in result.stdout
    assert f"Kernel modules source: {modules_src}" in result.stdout
    expected_dest = REPO_ROOT / "build" / "installer-initramfs" / "lib" / "modules" / kernel_version
    assert f"Kernel modules destination: {expected_dest}" in result.stdout


def test_runtime_chroot_directory_disambiguates(tmp_path: Path) -> None:
    kernel_version = "6.9.0-runtime"
    kernel_image = tmp_path / "vmlinuz-installer"
    _write_stub_kernel(kernel_image, kernel_version)

    runtime_modules = tmp_path / "runtime-chroot" / "lib" / "modules"
    (runtime_modules / kernel_version).mkdir(parents=True, exist_ok=True)

    modules_root = tmp_path / "modules-root"
    modules_src = modules_root / kernel_version

    result = _run_detection(
        {
            "SP_INSTALLER_KERNEL_IMAGE": str(kernel_image),
            "SP_INSTALLER_RUNTIME_CHROOT_MODULES": str(runtime_modules),
            "SP_INSTALLER_MODULES_ROOT": str(modules_root),
        }
    )

    assert result.returncode == 0
    assert "Kernel version detection method: runtime-chroot" in result.stdout
    assert f"Installer kernel version: {kernel_version}" in result.stdout
    assert f"Kernel modules source: {modules_src}" in result.stdout


def test_runtime_chroot_conflict_fails(tmp_path: Path) -> None:
    kernel_image = tmp_path / "vmlinuz-installer"
    _write_stub_kernel(kernel_image, "ignore.me")

    runtime_modules = tmp_path / "runtime-chroot" / "lib" / "modules"
    (runtime_modules / "6.7.0-one").mkdir(parents=True, exist_ok=True)
    (runtime_modules / "6.7.0-two").mkdir(parents=True, exist_ok=True)

    result = _run_detection(
        {
            "SP_INSTALLER_KERNEL_IMAGE": str(kernel_image),
            "SP_INSTALLER_RUNTIME_CHROOT_MODULES": str(runtime_modules),
        }
    )

    assert result.returncode != 0
    assert "Multiple kernel versions found" in result.stderr
    assert "set SP_INSTALLER_KERNEL_VERSION" in result.stderr


def test_detection_fails_when_everything_missing(tmp_path: Path) -> None:
    kernel_image = tmp_path / "vmlinuz-installer"
    _write_stub_kernel(kernel_image, "missing.version")
    runtime_modules = tmp_path / "runtime-chroot" / "lib" / "modules"

    result = _run_detection(
        {
            "SP_INSTALLER_KERNEL_IMAGE": str(kernel_image),
            "SP_INSTALLER_RUNTIME_CHROOT_MODULES": str(runtime_modules),
        }
    )

    assert result.returncode != 0
    assert "Unable to determine installer kernel version" in result.stderr
