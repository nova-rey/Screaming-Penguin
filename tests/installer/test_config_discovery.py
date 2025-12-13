"""Unit tests for the installer config discovery helper."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path("installer/runtime/lib/config_discovery.sh")
TEST_BIN = Path("tests/installer/bin")


def _run_command(
    env_overrides: dict[str, str], command: str
) -> subprocess.CompletedProcess:
    env = os.environ.copy()
    env.update(env_overrides)
    env["PATH"] = f"{TEST_BIN}{os.pathsep}{env.get('PATH', '')}"
    env.setdefault(
        "SP_RUNTIME_LIB_DIR",
        str((ROOT / "installer" / "runtime" / "lib").resolve()),
    )

    return subprocess.run(
        ["bash", "-c", command],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
    )


def _blkid_data_for(path: Path) -> str:
    return f"DEVNAME={path}\nLABEL={path.name}\nTYPE=vfat\n\n"


def test_prefers_label_device(tmp_path: Path) -> None:
    label_device = tmp_path / "label-device"
    label_device.mkdir()
    label_cfg = label_device / "installer-config.yml"
    label_cfg.write_text("label-config")

    scan_device = tmp_path / "scan-device"
    scan_device.mkdir()
    (scan_device / "installer-config.yml").write_text("scan-config")

    by_label = tmp_path / "by-label"
    by_label.mkdir()
    (by_label / "SP_CONFIG").symlink_to(label_device)

    blkid_file = tmp_path / "blkid.txt"
    blkid_file.write_text(_blkid_data_for(scan_device))
    lsblk_file = tmp_path / "lsblk.txt"
    lsblk_file.write_text("NAME FSTYPE\n")

    mount_point = tmp_path / "config-mount"

    command = f". {SCRIPT}; sp_discover_config && printf '%s' \"$SP_CONFIG_PATH\""
    env = {
        "SP_CONFIG_LABEL_DIR": str(by_label),
        "SP_CONFIG_MOUNT_POINT": str(mount_point),
        "SP_CONFIG_DISCOVERY_SLEEP": "0",
        "SP_CONFIG_DISCOVERY_MAX_ATTEMPTS": "2",
        "SP_TEST_BLKID_DATA": str(blkid_file),
        "SP_TEST_LSBLK_DATA": str(lsblk_file),
    }

    result = _run_command(env, command)

    assert result.returncode == 0
    assert result.stdout == str(mount_point / "installer-config.yml")
    assert (mount_point / "installer-config.yml").read_text() == "label-config"


def test_scans_vfat_when_label_missing(tmp_path: Path) -> None:
    scan_device = tmp_path / "scan-device"
    scan_device.mkdir()
    scan_cfg = scan_device / "installer-config.yml"
    scan_cfg.write_text("scan-config")

    by_label = tmp_path / "by-label"
    by_label.mkdir()

    blkid_file = tmp_path / "blkid.txt"
    blkid_file.write_text(_blkid_data_for(scan_device))
    lsblk_file = tmp_path / "lsblk.txt"
    lsblk_file.write_text("")

    mount_point = tmp_path / "config-mount"

    command = f". {SCRIPT}; sp_discover_config && printf '%s' \"$SP_CONFIG_PATH\""
    env = {
        "SP_CONFIG_LABEL_DIR": str(by_label),
        "SP_CONFIG_MOUNT_POINT": str(mount_point),
        "SP_CONFIG_DISCOVERY_SLEEP": "0",
        "SP_CONFIG_DISCOVERY_MAX_ATTEMPTS": "2",
        "SP_TEST_BLKID_DATA": str(blkid_file),
        "SP_TEST_LSBLK_DATA": str(lsblk_file),
    }

    result = _run_command(env, command)

    assert result.returncode == 0
    assert result.stdout == str(mount_point / "installer-config.yml")
    assert (mount_point / "installer-config.yml").read_text() == "scan-config"


def test_missing_config_triggers_rescue(tmp_path: Path) -> None:
    by_label = tmp_path / "by-label"
    by_label.mkdir()

    rescue_label_dir = tmp_path / "rescue-labels"
    rescue_label_dir.mkdir()
    (rescue_label_dir / "SP_CONFIG").write_text("candidate")

    blkid_file = tmp_path / "blkid.txt"
    blkid_file.write_text("")
    lsblk_file = tmp_path / "lsblk.txt"
    lsblk_file.write_text("NAME FSTYPE\n")

    mount_point = tmp_path / "config-mount"
    (tmp_path / "console").write_text("")
    shell_log = tmp_path / "rescue-shell.log"
    shell_log.write_text("")

    shell_exit = 47
    command = f". {SCRIPT}; sp_discover_config"

    env = {
        "SP_CONFIG_LABEL_DIR": str(by_label),
        "SP_CONFIG_MOUNT_POINT": str(mount_point),
        "SP_CONFIG_DISCOVERY_SLEEP": "0",
        "SP_CONFIG_DISCOVERY_MAX_ATTEMPTS": "1",
        "SP_TEST_BLKID_DATA": str(blkid_file),
        "SP_TEST_LSBLK_DATA": str(lsblk_file),
        "SP_RESCUE_LABEL_DIR": str(rescue_label_dir),
        "SP_TEST_RESCUE_SHELL": str(Path("tests/installer/bin/rescue-shell")),
        "SP_TEST_RESCUE_SHELL_EXIT": str(shell_exit),
        "SP_TEST_RESCUE_SHELL_LOG": str(shell_log),
        "SP_TEST_RESCUE_CONSOLE": str(tmp_path / "console"),
    }

    result = _run_command(env, command)

    assert result.returncode == shell_exit
    stderr_output = result.stderr
    assert "Entering rescue mode" in stderr_output
    assert "source=lsblk" in stderr_output
    assert "source=blkid" in stderr_output
    assert "source=by-label" in stderr_output
    shell_output = shell_log.read_text()
    assert "rescue-shell" in shell_output
