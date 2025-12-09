"""Tests for the Phase 12 bootloader helpers."""

from __future__ import annotations

import os
import shlex
import subprocess
import textwrap
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
BOOTLOADER_LIB = REPO_ROOT / "installer" / "runtime" / "lib" / "bootloader.sh"
ROOTFS_LIB = REPO_ROOT / "installer" / "runtime" / "lib" / "rootfs_deploy.sh"
DISK_EXECUTE_LIB = REPO_ROOT / "installer" / "runtime" / "lib" / "disk_execute.sh"


def _make_stub_bin(tmp_path: Path) -> Path:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()

    stub_common = textwrap.dedent(
        """
        #!/bin/sh
        log_dir="${SP_TEST_STUB_LOG_DIR:-/tmp}"
        printf '%s %s\n' "$(basename "$0")" "$*" >>"$log_dir/$(basename "$0").log"
        exit 0
        """
    ).strip()

    for name in ("mount", "umount"):
        path = bin_dir / name
        path.write_text(stub_common + "\n")
        path.chmod(0o755)

    blkid_script = textwrap.dedent(
        """
        #!/bin/sh
        part=""
        for arg in "$@"; do
            part="$arg"
        done
        case "$part" in
            /dev/mock-root)
                printf '%s\n' "${SP_TEST_BLKID_ROOT_UUID:-root-uuid}"
                ;;
            /dev/mock-efi)
                printf '%s\n' "${SP_TEST_BLKID_EFI_UUID:-efi-uuid}"
                ;;
            *)
                printf '%s\n' "${SP_TEST_BLKID_DEFAULT:-unknown}"
                ;;
        esac
        """
    ).strip()
    blkid_path = bin_dir / "blkid"
    blkid_path.write_text(blkid_script + "\n")
    blkid_path.chmod(0o755)

    chroot_script = textwrap.dedent(
        """
        #!/bin/sh
        log_dir="${SP_TEST_STUB_LOG_DIR:-/tmp}"
        printf '%s\n' "$(basename "$0") $@" >>"$log_dir/chroot.log"
        exit 0
        """
    ).strip()
    chroot_path = bin_dir / "chroot"
    chroot_path.write_text(chroot_script + "\n")
    chroot_path.chmod(0o755)

    return bin_dir


def _run_script(
    tmp_path: Path, script: str, env: dict[str, str] | None = None
) -> subprocess.CompletedProcess:
    base_env = os.environ.copy()
    base_env.update(
        {"PATH": f"{str(_make_stub_bin(tmp_path))}:{base_env.get('PATH', '')}"}
    )
    base_env["SP_TEST_STUB_LOG_DIR"] = str(tmp_path)
    base_env["SP_LOG_DEVICE"] = str(tmp_path / "bootloader.log")
    if env:
        base_env.update(env)

    return subprocess.run(
        ["/bin/bash", "-c", script],
        cwd=str(REPO_ROOT),
        env=base_env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def _script_preamble() -> str:
    return textwrap.dedent(
        """
        sp_log() { printf '[SP-INSTALLER] %s\n' "$*" >>"$SP_LOG_DEVICE"; }
        sp_trim() { printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }
        sp_enforce_write_gate() { return 0; }
        """
    )


def test_bootloader_generates_fstab(tmp_path: Path) -> None:
    target_dir = tmp_path / "target"
    target_dir.mkdir()
    quoted_target = shlex.quote(str(target_dir))

    script = textwrap.dedent(
        f"""
        { _script_preamble() }
        SP_ROOTFS_TARGET_DIR={quoted_target}
        SP_ROOTFS_TARGET_OVERRIDE_ACTIVE=1
        SP_DISK_EXECUTE_ROOT_PART=/dev/mock-root
        SP_DISK_EXECUTE_EFI_PART=/dev/mock-efi
        export SP_TEST_BLKID_ROOT_UUID=root-uuid
        export SP_TEST_BLKID_EFI_UUID=efi-uuid
        . "{ROOTFS_LIB}"
        . "{DISK_EXECUTE_LIB}"
        . "{BOOTLOADER_LIB}"
        sp_bootloader_generate_fstab
        """
    )

    result = _run_script(tmp_path, script)
    assert result.returncode == 0, result.stderr
    contents = (target_dir / "etc" / "fstab").read_text()
    assert "UUID=root-uuid / ext4 defaults,noatime 0 1" in contents
    assert (
        "UUID=efi-uuid /boot/efi vfat umask=0077,fmask=0077,dmask=0077 0 2" in contents
    )


def test_bootloader_install_grub_uses_expected_arguments(tmp_path: Path) -> None:
    target_dir = tmp_path / "target"
    (target_dir / "boot").mkdir(parents=True)
    target_path = shlex.quote(str(target_dir))
    efi_path = shlex.quote(str(target_dir / "boot" / "efi"))

    script = textwrap.dedent(
        f"""
        { _script_preamble() }
        SP_ROOTFS_TARGET_DIR={target_path}
        SP_BOOTLOADER_EFI_PATH={efi_path}
        mkdir -p {efi_path}
        . "{ROOTFS_LIB}"
        . "{DISK_EXECUTE_LIB}"
        . "{BOOTLOADER_LIB}"
        sp_bootloader_install_grub
        """
    )

    result = _run_script(tmp_path, script)
    assert result.returncode == 0, result.stderr
    log_path = tmp_path / "chroot.log"
    assert log_path.exists()
    entry = log_path.read_text().strip()
    assert "grub-install" in entry
    assert "--target=x86_64-efi" in entry
    assert "--efi-directory" in entry
    assert "--bootloader-id=screaming-penguin" in entry


def test_bootloader_stage_skips_when_toggle_disabled(tmp_path: Path) -> None:
    target_dir = tmp_path / "target"
    target_dir.mkdir()
    target_path = shlex.quote(str(target_dir))

    script = textwrap.dedent(
        f"""
        { _script_preamble() }
        SP_ROOTFS_TARGET_DIR={target_path}
        SP_ROOTFS_TARGET_OVERRIDE_ACTIVE=1
        SP_ENABLE_DISK_EXECUTE=1
        SP_MODE=INSTALL
        SP_ENABLE_BOOTLOADER=0
        . "{ROOTFS_LIB}"
        . "{DISK_EXECUTE_LIB}"
        . "{BOOTLOADER_LIB}"
        sp_install_bootloader_and_finalize
        """
    )

    result = _run_script(tmp_path, script)
    assert result.returncode == 0, result.stderr
    log = (tmp_path / "bootloader.log").read_text()
    assert "state=bootloader" in log
    assert "result=skipped" in log
    assert "reason=toggle-disabled" in log


def test_bootloader_stage_runs_when_enabled(tmp_path: Path) -> None:
    target_dir = tmp_path / "target"
    (target_dir / "boot").mkdir(parents=True)
    (target_dir / "boot" / "vmlinuz-test").write_text("kernel")
    (target_dir / "boot" / "initrd.img").write_text("initrd")
    target_path = shlex.quote(str(target_dir))

    script = textwrap.dedent(
        f"""
        { _script_preamble() }
        SP_ROOTFS_TARGET_DIR={target_path}
        SP_ROOTFS_TARGET_OVERRIDE_ACTIVE=1
        SP_ROOTFS_TARGET_DIR_OVERRIDE={target_path}
        SP_DISK_EXECUTE_ROOT_PART=/dev/mock-root
        SP_DISK_EXECUTE_EFI_PART=/dev/mock-efi
        export SP_TEST_BLKID_ROOT_UUID=root-uuid
        export SP_TEST_BLKID_EFI_UUID=efi-uuid
        SP_ENABLE_DISK_EXECUTE=1
        SP_MODE=INSTALL
        SP_ENABLE_BOOTLOADER=1
        . "{ROOTFS_LIB}"
        . "{DISK_EXECUTE_LIB}"
        . "{BOOTLOADER_LIB}"
        sp_install_bootloader_and_finalize
        """
    )

    result = _run_script(tmp_path, script)
    assert result.returncode == 0, result.stderr
    log = (tmp_path / "bootloader.log").read_text()
    assert "state=bootloader" in log
    assert "result=ok" in log
    assert (target_dir / "boot" / "grub" / "grub.cfg").exists()
