"""BusyBox-only config discovery tests."""

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
    test_bin_path = str((ROOT / TEST_BIN).resolve())
    env["PATH"] = f"{test_bin_path}{os.pathsep}{env.get('PATH', '')}"
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


def _setup_sys_dev(tmp_path: Path) -> tuple[Path, Path]:
    sys_block = tmp_path / "sys" / "block"
    dev_root = tmp_path / "dev"
    sys_block.mkdir(parents=True, exist_ok=True)
    dev_root.mkdir(parents=True, exist_ok=True)
    return sys_block, dev_root


def _create_block(tmp_path: Path, name: str, removable: str = "0") -> Path:
    sys_block, dev_root = _setup_sys_dev(tmp_path)
    block_dir = sys_block / name
    block_dir.mkdir(exist_ok=True)
    (block_dir / "removable").write_text(removable)
    device = dev_root / name
    device.mkdir(exist_ok=True)
    _record_proc_partition(tmp_path, name)
    return device


def _create_partition(tmp_path: Path, parent: str, partition: str) -> Path:
    sys_block, dev_root = _setup_sys_dev(tmp_path)
    parent_dir = sys_block / parent
    parent_dir.mkdir(exist_ok=True)
    part_dir = parent_dir / partition
    part_dir.mkdir(exist_ok=True)
    device = dev_root / partition
    device.mkdir(exist_ok=True)
    _record_proc_partition(tmp_path, partition)
    return device


def _ensure_proc_partitions(tmp_path: Path) -> Path:
    partitions = tmp_path / "proc_partitions"
    if not partitions.exists():
        partitions.write_text("major minor #blocks name\n")
    return partitions


def _record_proc_partition(tmp_path: Path, name: str) -> None:
    partitions = _ensure_proc_partitions(tmp_path)
    with partitions.open("a") as stream:
        stream.write(f"   8     1    1024 {name}\n")


def _base_env(tmp_path: Path) -> dict[str, str]:
    sys_block = tmp_path / "sys" / "block"
    dev_root = tmp_path / "dev"
    label_dir = tmp_path / "by-label"
    mount_point = tmp_path / "config"
    label_dir.mkdir(parents=True, exist_ok=True)
    sys_block.mkdir(parents=True, exist_ok=True)
    dev_root.mkdir(parents=True, exist_ok=True)
    partitions = _ensure_proc_partitions(tmp_path)
    return {
        "SP_SYS_BLOCK_ROOT": str(sys_block),
        "SP_DEV_ROOT": str(dev_root),
        "SP_CONFIG_LABEL_DIR": str(label_dir),
        "SP_CONFIG_MOUNT_POINT": str(mount_point),
        "SP_PROC_PARTITIONS": str(partitions),
    }


def _configure_rescue_env(env: dict[str, str], tmp_path: Path) -> Path:
    shell_log = tmp_path / "rescue-shell.log"
    console = tmp_path / "console"
    console.write_text("")
    env.update(
        {
            "SP_TEST_RESCUE_SHELL": str(Path("tests/installer/bin/rescue-shell")),
            "SP_TEST_RESCUE_SHELL_EXIT": "47",
            "SP_TEST_RESCUE_SHELL_LOG": str(shell_log),
            "SP_TEST_RESCUE_CONSOLE": str(console),
            "SP_TEST_RESCUE_LOOP": "0",
        }
    )
    return shell_log


def _write_usb_scan_trigger_script(tmp_path: Path) -> Path:
    script = tmp_path / "usb-scan-trigger.sh"
    script.write_text(
        "#!/bin/sh\n"
        "sys_block=\"$1\"\n"
        "dev_root=\"$2\"\n"
        "device_name=\"${SP_TEST_USB_STORAGE_SCAN_DEVICE:-sda}\"\n"
        "config_content=\"${SP_TEST_USB_STORAGE_SCAN_CONFIG:-usb-scan}\"\n"
        "removable_value=\"${SP_TEST_USB_STORAGE_SCAN_REMOVABLE:-1}\"\n"
        "mkdir -p \"$sys_block/$device_name\"\n"
        "mkdir -p \"$dev_root/$device_name\"\n"
        "printf '%s\\n' \"$removable_value\" > \"$sys_block/$device_name/removable\"\n"
        "printf '%s\\n' \"$config_content\" > \"$dev_root/$device_name/installer-config.yml\"\n"
    )
    script.chmod(0o755)
    return script


def _assert_config_found(
    result: subprocess.CompletedProcess, expected_content: str, mount_point: Path
) -> None:
    assert result.returncode == 0, result.stderr
    lines = result.stdout.strip().splitlines()
    assert lines[0] == str(mount_point / "installer-config.yml")
    assert lines[1] == str(mount_point)
    assert (mount_point / "installer-config.yml").read_text() == expected_content


def test_prefers_label_device(tmp_path: Path) -> None:
    label_device = _create_block(tmp_path, "label-disk")
    (label_device / "installer-config.yml").write_text("config\n")

    removable_device = _create_block(tmp_path, "rem-disk", removable="1")
    (removable_device / "installer-config.yml").write_text("removable\n")

    label_dir = tmp_path / "by-label"
    label_dir.mkdir(parents=True, exist_ok=True)
    (label_dir / "SP_CONFIG").symlink_to(label_device)

    blkid_data = tmp_path / "label-blkid.dat"
    blkid_data.write_text(
        f"DEVNAME={label_device}\n"
        "LABEL=SP_CONFIG\n"
    )

    env = _base_env(tmp_path)
    env["SP_TEST_BLKID_DATA"] = str(blkid_data)
    command = f'. {SCRIPT}; if sp_discover_config; then printf \'%s\\n%s\\n\' "$SP_CONFIG_PATH" "$CONFIG_MOUNT"; fi'
    result = _run_command(env, command)

    _assert_config_found(result, "config\n", Path(env["SP_CONFIG_MOUNT_POINT"]))


def test_probe_label_selects_device(tmp_path: Path) -> None:
    label_device = _create_block(tmp_path, "label-disk")
    (label_device / "installer-config.yml").write_text("config\n")

    blkid_data = tmp_path / "blkid.dat"
    blkid_data.write_text(
        f"DEVNAME={label_device}\n"
        "LABEL=SP_CONFIG\n"
    )

    env = _base_env(tmp_path)
    env["SP_TEST_BLKID_DATA"] = str(blkid_data)

    command = f'. {SCRIPT}; if sp_discover_config; then printf \'%s\\n%s\\n\' "$SP_CONFIG_PATH" "$CONFIG_MOUNT"; fi'
    result = _run_command(env, command)

    _assert_config_found(result, "config\n", Path(env["SP_CONFIG_MOUNT_POINT"]))


def test_mount_falls_back_to_ext4(tmp_path: Path) -> None:
    fallback_device = _create_block(tmp_path, "fallback", removable="0")
    (fallback_device / "installer-config.yml").write_text("fallback-config\n")

    env = _base_env(tmp_path)
    env["SP_CONFIG_FS_TYPES"] = " vfat , ext4 "
    env["SP_TEST_MOUNT_FAIL_FS"] = "vfat"

    blkid_data = tmp_path / "fallback-blkid.dat"
    blkid_data.write_text(
        f"DEVNAME={fallback_device}\n"
        "LABEL=SP_CONFIG\n"
    )
    env["SP_TEST_BLKID_DATA"] = str(blkid_data)

    command = f'. {SCRIPT}; if sp_discover_config; then printf \'%s\\n%s\\n\' "$SP_CONFIG_PATH" "$CONFIG_MOUNT"; fi'
    result = _run_command(env, command)

    _assert_config_found(result, "fallback-config\n", Path(env["SP_CONFIG_MOUNT_POINT"]))
    expected_device = Path(env["SP_DEV_ROOT"]) / "fallback"
    expected_log = f"config-mount-ok fstype=ext4 dev={expected_device} mnt={env['SP_CONFIG_MOUNT_POINT']}"
    assert expected_log in result.stderr


def test_probe_label_not_found_fatal(tmp_path: Path) -> None:
    label_device = _create_block(tmp_path, "label-disk")

    blkid_data = tmp_path / "blkid.dat"
    blkid_data.write_text(
        f"DEVNAME={label_device}\n"
        "LABEL=OTHER\n"
    )

    env = _base_env(tmp_path)
    env["SP_TEST_BLKID_DATA"] = str(blkid_data)
    env["SP_CONFIG_LABEL"] = "SP_CONFIG"
    shell_log = _configure_rescue_env(env, tmp_path)

    result = _run_command(env, f". {SCRIPT}; sp_discover_config")

    assert result.returncode == 1
    assert "[SP-INSTALLER][FATAL] label-not-found label=SP_CONFIG probed=1" in result.stderr
    assert not shell_log.exists()


def test_label_probe_uses_blkid_without_dev_disk_by_label(tmp_path: Path) -> None:
    partition_one = _create_partition(tmp_path, "sda", "sda1")
    (partition_one / "installer-config.yml").write_text("config\n")
    _create_partition(tmp_path, "sda", "sda2")

    env = _base_env(tmp_path)
    dev_root = Path(env["SP_DEV_ROOT"])
    blkid_data = tmp_path / "multi-blkid.dat"
    blkid_data.write_text(
        f"DEVNAME={dev_root / 'sda1'}\n"
        "LABEL=SP_CONFIG\n"
        "\n"
        f"DEVNAME={dev_root / 'sda2'}\n"
        "LABEL=\n"
    )
    env["SP_CONFIG_LABEL"] = "SP_CONFIG"
    env["SP_TEST_BLKID_DATA"] = str(blkid_data)
    command = f'. {SCRIPT}; if sp_discover_config; then printf \'%s\\n%s\\n\' "$SP_CONFIG_PATH" "$CONFIG_MOUNT"; fi'
    result = _run_command(env, command)

    expected_device = Path(env["SP_DEV_ROOT"]) / "sda1"
    assert result.returncode == 0, result.stderr
    assert f"label-probe device={expected_device}" in result.stderr
    assert f"SP_CONFIG_LABEL_DEVICE={expected_device}" in result.stderr
    assert "/dev/disk/by-label" not in result.stderr
    _assert_config_found(result, "config\n", Path(env["SP_CONFIG_MOUNT_POINT"]))


def test_label_probe_fails_fast_when_blkid_missing(tmp_path: Path) -> None:
    env = _base_env(tmp_path)
    env["SP_CONFIG_LABEL"] = "SP_CONFIG"
    env["SP_TEST_BLKID_MISSING"] = "1"
    shell_log = _configure_rescue_env(env, tmp_path)

    result = _run_command(env, f". {SCRIPT}; sp_discover_config")

    assert result.returncode == 1
    assert "[SP-INSTALLER][FATAL] missing-blkid-for-label-probe" in result.stderr
    assert not shell_log.exists()


def test_uses_removable_when_label_missing(tmp_path: Path) -> None:
    removable_device = _create_block(tmp_path, "bus-disk", removable="1")
    (removable_device / "installer-config.yml").write_text("removable\n")

    env = _base_env(tmp_path)
    command = f'. {SCRIPT}; if sp_discover_config; then printf \'%s\\n%s\\n\' "$SP_CONFIG_PATH" "$CONFIG_MOUNT"; fi'
    result = _run_command(env, command)

    _assert_config_found(result, "removable\n", Path(env["SP_CONFIG_MOUNT_POINT"]))


def test_waits_for_usb_storage_scan_trigger(tmp_path: Path) -> None:
    env = _base_env(tmp_path)
    trigger = _write_usb_scan_trigger_script(tmp_path)
    scan_value = "delayed-scan"
    env.update(
        {
            "SP_TEST_USB_STORAGE_SCAN_TRIGGER": str(trigger),
            "SP_TEST_USB_STORAGE_SCAN_CONFIG": scan_value,
        }
    )

    command = f'. {SCRIPT}; if sp_discover_config; then printf \'%s\\n%s\\n\' "$SP_CONFIG_PATH" "$CONFIG_MOUNT"; fi'
    result = _run_command(env, command)

    _assert_config_found(
        result,
        f"{scan_value}\n",
        Path(env["SP_CONFIG_MOUNT_POINT"]),
    )


def test_usb_storage_scan_noop_with_existing_device(tmp_path: Path) -> None:
    existing_device = _create_block(tmp_path, "present", removable="1")
    (existing_device / "installer-config.yml").write_text("present\n")

    trigger = tmp_path / "usb-scan-noop.sh"
    trigger.write_text("#!/bin/sh\nexit 0\n")
    trigger.chmod(0o755)

    env = _base_env(tmp_path)
    env["SP_TEST_USB_STORAGE_SCAN_TRIGGER"] = str(trigger)

    command = f'. {SCRIPT}; if sp_discover_config; then printf \'%s\\n%s\\n\' "$SP_CONFIG_PATH" "$CONFIG_MOUNT"; fi'
    result = _run_command(env, command)

    _assert_config_found(
        result,
        "present\n",
        Path(env["SP_CONFIG_MOUNT_POINT"]),
    )


def test_falls_back_to_partitions(tmp_path: Path) -> None:
    _create_block(tmp_path, "stable", removable="0")
    partition_device = _create_partition(tmp_path, "stable", "stable1")
    (partition_device / "installer-config.yml").write_text("partition\n")

    env = _base_env(tmp_path)
    command = f'. {SCRIPT}; if sp_discover_config; then printf \'%s\\n%s\\n\' "$SP_CONFIG_PATH" "$CONFIG_MOUNT"; fi'
    result = _run_command(env, command)

    _assert_config_found(result, "partition\n", Path(env["SP_CONFIG_MOUNT_POINT"]))


def test_missing_config_triggers_rescue(tmp_path: Path) -> None:
    _create_block(tmp_path, "faulty", removable="0")

    env = _base_env(tmp_path)
    shell_log = _configure_rescue_env(env, tmp_path)

    result = _run_command(env, f". {SCRIPT}; sp_discover_config")

    assert result.returncode == 47
    stderr = result.stderr
    assert "Entering rescue mode" in stderr
    assert "source=sysfs" in stderr
    assert "source=proc/partitions" in stderr
    assert "source=by-label" in stderr
    assert shell_log.exists()
    assert "rescue-shell" in shell_log.read_text()


def test_respects_exclude_prefix(tmp_path: Path) -> None:
    skip_device = _create_block(tmp_path, "skip-disk", removable="1")
    (skip_device / "installer-config.yml").write_text("skip\n")

    allowed_device = _create_block(tmp_path, "z-disk", removable="1")
    (allowed_device / "installer-config.yml").write_text("allowed\n")

    env = _base_env(tmp_path)
    env["SP_CONFIG_DISCOVERY_EXCLUDE_PREFIXES"] = "skip"

    command = f'. {SCRIPT}; if sp_discover_config; then printf \'%s\\n%s\\n\' "$SP_CONFIG_PATH" "$CONFIG_MOUNT"; fi'
    result = _run_command(env, command)

    _assert_config_found(result, "allowed\n", Path(env["SP_CONFIG_MOUNT_POINT"]))


def test_uses_heuristic_partition_names(tmp_path: Path) -> None:
    env = _base_env(tmp_path)

    sys_block = tmp_path / "sys" / "block"
    dev_root = tmp_path / "dev"
    (sys_block / "sda").mkdir(exist_ok=True)
    partition_device = dev_root / "sda1"
    partition_device.mkdir(exist_ok=True)
    (partition_device / "installer-config.yml").write_text("heuristic\n")

    command = f'. {SCRIPT}; if sp_discover_config; then printf \'%s\\n%s\\n\' "$SP_CONFIG_PATH" "$CONFIG_MOUNT"; fi'
    result = _run_command(env, command)

    assert result.returncode == 0, result.stderr
    assert "phase=partition-heuristic" in result.stderr
    _assert_config_found(result, "heuristic\n", Path(env["SP_CONFIG_MOUNT_POINT"]))


def test_runtime_has_no_util_linux_references() -> None:
    runtime_dir = ROOT / "installer" / "runtime"
    for path in runtime_dir.rglob("*"):
        if not path.is_file():
            continue
        text = path.read_text(errors="ignore")
        if path.name == "config_discovery.sh":
            assert "lsblk" not in text, f"lsblk reference found in {path}"
            continue
        assert "blkid" not in text, f"blkid reference found in {path}"
        assert "lsblk" not in text, f"lsblk reference found in {path}"
