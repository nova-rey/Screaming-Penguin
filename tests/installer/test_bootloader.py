"""Tests validating the bootloader stage helpers."""

from __future__ import annotations

import os
import subprocess
import textwrap
from pathlib import Path

INIT_SCRIPT = Path("installer/init/init.sh")


def _write_stub(path: Path, contents: str) -> None:
    path.write_text(textwrap.dedent(contents).strip() + "\n")
    path.chmod(0o755)


def _make_bootloader_bin(
    base: Path,
    root_part: str,
    efi_part: str,
    root_uuid: str | None = None,
    efi_uuid: str | None = None,
    chroot_log: Path | None = None,
    grub_log: Path | None = None,
) -> Path:
    bin_dir = base / "bin"
    bin_dir.mkdir()

    if root_uuid is not None and efi_uuid is not None:
        _write_stub(
            bin_dir / "blkid",
            """
            #!/bin/sh
            device=""
            for arg in "$@"; do
                device="$arg"
            done

            case "$device" in
                "$TEST_ROOT_PART")
                    printf '%s' "$TEST_ROOT_UUID"
                    exit 0
                    ;;
                "$TEST_EFI_PART")
                    printf '%s' "$TEST_EFI_UUID"
                    exit 0
                    ;;
                *)
                    exit 1
                    ;;
            esac
            """,
        )
    else:
        _write_stub(bin_dir / "blkid", "#!/bin/sh\nexit 0\n")

    _write_stub(
        bin_dir / "mountpoint",
        """
        #!/bin/sh
        exit 0
        """,
    )
    _write_stub(
        bin_dir / "mount",
        """
        #!/bin/sh
        exit 0
        """,
    )
    _write_stub(
        bin_dir / "umount",
        """
        #!/bin/sh
        exit 0
        """,
    )

    if chroot_log is not None:
        _write_stub(
            bin_dir / "chroot",
            """
            #!/bin/sh
            printf '%s\n' "$*" >> "$CHROOT_LOG"
            exit 0
            """,
        )
    else:
        _write_stub(bin_dir / "chroot", "#!/bin/sh\nexit 0\n")

    if grub_log is not None:
        _write_stub(
            bin_dir / "grub-install",
            """
            #!/bin/sh
            printf '%s\\n' "$*" >> "$GRUB_INSTALL_LOG"
            exit 0
            """,
        )
    else:
        _write_stub(bin_dir / "grub-install", "#!/bin/sh\nexit 0\n")

    return bin_dir


def _run_with_init(
    tmp_path: Path,
    command: str,
    bin_dir: Path | None = None,
    env_updates: dict[str, str] | None = None,
) -> subprocess.CompletedProcess:
    console_log = tmp_path / "console.log"
    serial_log = tmp_path / "serial.log"
    console_log.write_text("")
    serial_log.write_text("")

    env = os.environ.copy()
    env.update(
        {
            "SP_SKIP_INIT_MAIN": "1",
            "SP_MODE": "INSTALL",
            "SP_ENABLE_DISK_EXECUTE": "1",
            "SP_ENABLE_BOOTLOADER": "1",
            "SP_SKIP_BOOTLOADER": "0",
            "SP_BOOTLOADER_READY": "1",
            "SP_LOG_DEVICE": str(console_log),
            "SP_WRITE_GATE_SERIAL_DEVICE": str(serial_log),
            "SP_INIT_SCRIPT_PATH": str(INIT_SCRIPT.resolve()),
        }
    )

    if bin_dir is not None:
        env["PATH"] = f"{bin_dir}:{env.get('PATH', '')}"

    if env_updates:
        env.update(env_updates)

    return subprocess.run(
        ["/bin/sh", "-c", f". {INIT_SCRIPT} && {command}"],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def _write_config(tmp_path: Path) -> Path:
    config_path = tmp_path / "installer-config.yml"
    config_path.write_text(
        textwrap.dedent(
            """
        installer:
          write_gate: true
    """
        )
    )
    return config_path


def test_bootloader_rewrites_fstab(tmp_path: Path) -> None:
    target_dir = tmp_path / "target"
    target_dir.mkdir()
    (target_dir / "etc").mkdir()

    root_part = "/dev/test-root"
    efi_part = "/dev/test-efi"
    root_uuid = "ROOT-UUID"
    efi_uuid = "EFI-UUID"

    chroot_log = tmp_path / "chroot.log"
    bin_dir = _make_bootloader_bin(
        tmp_path, root_part, efi_part, root_uuid, efi_uuid, chroot_log, None
    )

    config_path = _write_config(tmp_path)

    result = _run_with_init(
        tmp_path,
        "sp_bootloader_generate_fstab",
        bin_dir=bin_dir,
        env_updates={
            "SP_TARGET_MNT": str(target_dir),
            "SP_TARGET_PART_ROOT": root_part,
            "SP_TARGET_PART_BOOT": efi_part,
            "SP_DISK_EXECUTE_ROOT_PART": root_part,
            "SP_DISK_EXECUTE_EFI_PART": efi_part,
            "TEST_ROOT_PART": root_part,
            "TEST_EFI_PART": efi_part,
            "TEST_ROOT_UUID": root_uuid,
            "TEST_EFI_UUID": efi_uuid,
            "SP_CONFIG_PATH": str(config_path),
        },
    )

    assert result.returncode == 0, result.stderr
    fstab = (target_dir / "etc" / "fstab").read_text()
    assert "UUID=ROOT-UUID / ext4" in fstab
    assert "UUID=EFI-UUID /boot/efi vfat" in fstab


def test_bootloader_chroot_debug_logs(tmp_path: Path) -> None:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    _write_stub(
        bin_dir / "chroot",
        """
        #!/bin/sh
        printf '%s\n' "$*" >> "$CHROOT_LOG"
        exit 0
        """,
    )
    _write_stub(
        bin_dir / "mountpoint",
        """
        #!/bin/sh
        exit 0
        """,
    )
    _write_stub(
        bin_dir / "mount",
        """
        #!/bin/sh
        exit 0
        """,
    )
    _write_stub(
        bin_dir / "umount",
        """
        #!/bin/sh
        exit 0
        """,
    )

    chroot_log = tmp_path / "chroot-debug.log"
    result = _run_with_init(
        tmp_path,
        "sp_bootloader_chroot_exec 'echo hello'",
        bin_dir=bin_dir,
        env_updates={
            "SP_TARGET_MNT": "/mnt/target",
            "SP_DEBUG_BOOTLOADER": "1",
            "CHROOT_LOG": str(chroot_log),
        },
    )

    assert result.returncode == 0
    chroot_records = chroot_log.read_text().strip().splitlines()
    assert any("echo hello" in line for line in chroot_records)
    console_log = (tmp_path / "console.log").read_text()
    assert "debug=chroot-cmd" in console_log


def test_bootloader_stage_runs_with_toggle(tmp_path: Path) -> None:
    target_dir = tmp_path / "target"
    (target_dir / "etc").mkdir(parents=True)
    (target_dir / "boot" / "grub").mkdir(parents=True)

    root_part = "/dev/test-root"
    efi_part = "/dev/test-efi"
    root_uuid = "RUN-ROOT-UUID"
    efi_uuid = "RUN-EFI-UUID"

    chroot_log = tmp_path / "chroot.log"
    grub_log = tmp_path / "grub-install.log"
    bin_dir = _make_bootloader_bin(
        tmp_path, root_part, efi_part, root_uuid, efi_uuid, chroot_log, grub_log
    )

    config_path = _write_config(tmp_path)

    result = _run_with_init(
        tmp_path,
        "sp_install_bootloader_and_finalize",
        bin_dir=bin_dir,
        env_updates={
            "SP_TARGET_MNT": str(target_dir),
            "SP_TARGET_PART_ROOT": root_part,
            "SP_TARGET_PART_BOOT": efi_part,
            "SP_DISK_EXECUTE_ROOT_PART": root_part,
            "SP_DISK_EXECUTE_EFI_PART": efi_part,
            "TEST_ROOT_PART": root_part,
            "TEST_EFI_PART": efi_part,
            "TEST_ROOT_UUID": root_uuid,
            "TEST_EFI_UUID": efi_uuid,
            "SP_CONFIG_PATH": str(config_path),
            "CHROOT_LOG": str(chroot_log),
        },
    )

    assert result.returncode == 0
    console_log = (tmp_path / "console.log").read_text()
    assert "state=bootloader" in console_log
    assert "marker=START" in console_log
    assert "marker=END" in console_log
    assert (target_dir / "etc" / "fstab").exists()
    assert (target_dir / "boot" / "grub" / "grub.cfg").exists()
    chroot_lines = chroot_log.read_text()
    assert "grub-install" in chroot_lines


def test_bootloader_skip_toggle(tmp_path: Path) -> None:
    target_dir = tmp_path / "target"
    target_dir.mkdir()

    root_part = "/dev/test-root"
    efi_part = "/dev/test-efi"
    root_uuid = "SKIP-ROOT-UUID"
    efi_uuid = "SKIP-EFI-UUID"

    bin_dir = _make_bootloader_bin(
        tmp_path, root_part, efi_part, root_uuid, efi_uuid, None, None
    )

    config_path = _write_config(tmp_path)

    result = _run_with_init(
        tmp_path,
        "sp_install_bootloader_and_finalize",
        bin_dir=bin_dir,
        env_updates={
            "SP_TARGET_MNT": str(target_dir),
            "SP_TARGET_PART_ROOT": root_part,
            "SP_TARGET_PART_BOOT": efi_part,
            "SP_DISK_EXECUTE_ROOT_PART": root_part,
            "SP_DISK_EXECUTE_EFI_PART": efi_part,
            "TEST_ROOT_PART": root_part,
            "TEST_EFI_PART": efi_part,
            "TEST_ROOT_UUID": root_uuid,
            "TEST_EFI_UUID": efi_uuid,
            "SP_CONFIG_PATH": str(config_path),
            "SP_SKIP_BOOTLOADER": "1",
        },
    )

    assert result.returncode == 0
    console_log = (tmp_path / "console.log").read_text()
    assert "reason=skip-flag" in console_log
    assert not (target_dir / "etc" / "fstab").exists()


def test_bootloader_toggle_disabled(tmp_path: Path) -> None:
    target_dir = tmp_path / "target"
    target_dir.mkdir()

    root_part = "/dev/test-root"
    efi_part = "/dev/test-efi"
    root_uuid = "STOP-ROOT-UUID"
    efi_uuid = "STOP-EFI-UUID"

    chroot_log = tmp_path / "chroot.log"
    grub_log = tmp_path / "grub-install.log"
    bin_dir = _make_bootloader_bin(
        tmp_path, root_part, efi_part, root_uuid, efi_uuid, chroot_log, grub_log
    )

    config_path = _write_config(tmp_path)

    result = _run_with_init(
        tmp_path,
        "sp_install_bootloader_and_finalize",
        bin_dir=bin_dir,
        env_updates={
            "SP_TARGET_MNT": str(target_dir),
            "SP_TARGET_PART_ROOT": root_part,
            "SP_TARGET_PART_BOOT": efi_part,
            "SP_DISK_EXECUTE_ROOT_PART": root_part,
            "SP_DISK_EXECUTE_EFI_PART": efi_part,
            "TEST_ROOT_PART": root_part,
            "TEST_EFI_PART": efi_part,
            "TEST_ROOT_UUID": root_uuid,
            "TEST_EFI_UUID": efi_uuid,
            "SP_CONFIG_PATH": str(config_path),
            "SP_ENABLE_BOOTLOADER": "0",
            "CHROOT_LOG": str(chroot_log),
            "GRUB_INSTALL_LOG": str(grub_log),
        },
    )

    assert result.returncode == 0
    console_log = (tmp_path / "console.log").read_text()
    assert "reason=toggle-disabled" in console_log
