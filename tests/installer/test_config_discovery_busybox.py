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
    env["PATH"] = f"{TEST_BIN}{os.pathsep}{env.get('PATH', '')}"
    env.setdefault(
        "SP_RUNTIME_LIB_DIR",
        str((ROOT / "installer" / "runtime" / "lib").resolve()),
    )
    env.setdefault("SP_TEST_RESCUE_SHELL", str(Path("tests/installer/bin/rescue-shell")))
    env.setdefault("SP_TEST_RESCUE_SHELL_EXIT", "47")
    env.setdefault("SP_TEST_RESCUE_LOOP", "0")

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
    return device


def _create_partition(
    tmp_path: Path, parent: str, partition: str, removable: str = "0"
) -> Path:
    sys_block, dev_root = _setup_sys_dev(tmp_path)
    parent_dir = sys_block / parent
    parent_dir.mkdir(exist_ok=True)
    (parent_dir / "removable").write_text(removable)
    part_dir = parent_dir / partition
    part_dir.mkdir(exist_ok=True)
    device = dev_root / partition
    device.mkdir(exist_ok=True)
    return device


def _populate_config_media(
    device: Path,
    config_content: str = "config\n",
    rootfs_names: tuple[str, ...] = ("rootfs.tar.gz",),
) -> None:
    (device / "installer-config.yml").write_text(config_content)
    os_dir = device / "os"
    os_dir.mkdir(parents=True, exist_ok=True)
    for name in rootfs_names:
        (os_dir / name).write_text("rootfs\n")


def _base_env(tmp_path: Path) -> dict[str, str]:
    sys_block = tmp_path / "sys" / "block"
    dev_root = tmp_path / "dev"
    label_dir = tmp_path / "by-label"
    mount_point = tmp_path / "config"
    label_dir.mkdir(parents=True, exist_ok=True)
    sys_block.mkdir(parents=True, exist_ok=True)
    dev_root.mkdir(parents=True, exist_ok=True)
    return {
        "SP_SYS_BLOCK_ROOT": str(sys_block),
        "SP_DEV_ROOT": str(dev_root),
        "SP_CONFIG_LABEL_DIR": str(label_dir),
        "SP_CONFIG_MOUNT_POINT": str(mount_point),
    }


def _assert_config_found(
    result: subprocess.CompletedProcess, expected_content: str, mount_point: Path
) -> None:
    assert result.returncode == 0, result.stderr
    lines = result.stdout.strip().splitlines()
    assert lines[0] == str(mount_point / "installer-config.yml")
    assert lines[1] == str(mount_point)
    assert (mount_point / "installer-config.yml").read_text() == expected_content


def test_prefers_label_device(tmp_path: Path) -> None:
    label_device = _create_block(tmp_path, "label-disk", removable="1")
    _populate_config_media(label_device, "config\n")

    removable_device = _create_block(tmp_path, "rem-disk", removable="1")
    (removable_device / "installer-config.yml").write_text("removable\n")

    label_dir = tmp_path / "by-label"
    label_dir.mkdir(parents=True, exist_ok=True)
    (label_dir / "SP_CONFIG").symlink_to(label_device)

    env = _base_env(tmp_path)
    command = f'. {SCRIPT}; if sp_discover_config; then printf \'%s\\n%s\\n\' "$SP_CONFIG_PATH" "$CONFIG_MOUNT"; fi'
    result = _run_command(env, command)

    _assert_config_found(result, "config\n", Path(env["SP_CONFIG_MOUNT_POINT"]))
    assert "config-source=label:SP_CONFIG" in result.stderr


def test_uses_removable_when_label_missing(tmp_path: Path) -> None:
    removable_device = _create_partition(tmp_path, "bus-disk", "bus-disk1", removable="1")
    _populate_config_media(removable_device, "removable\n")

    env = _base_env(tmp_path)
    command = f'. {SCRIPT}; if sp_discover_config; then printf \'%s\\n%s\\n\' "$SP_CONFIG_PATH" "$CONFIG_MOUNT"; fi'
    result = _run_command(env, command)

    _assert_config_found(result, "removable\n", Path(env["SP_CONFIG_MOUNT_POINT"]))
    assert "config-source=removable:bus-disk1" in result.stderr


def test_removable_fallback_scans_partitions(tmp_path: Path) -> None:
    partition_device = _create_partition(tmp_path, "stable", "stable1", removable="1")
    _populate_config_media(partition_device, "partition\n")

    env = _base_env(tmp_path)
    command = f'. {SCRIPT}; if sp_discover_config; then printf \'%s\\n%s\\n\' "$SP_CONFIG_PATH" "$CONFIG_MOUNT"; fi'
    result = _run_command(env, command)

    _assert_config_found(result, "partition\n", Path(env["SP_CONFIG_MOUNT_POINT"]))
    assert "phase=removable" in result.stderr


def test_missing_config_triggers_rescue(tmp_path: Path) -> None:
    _create_partition(tmp_path, "faulty", "faulty1", removable="1")

    env = _base_env(tmp_path)
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

    result = _run_command(env, f". {SCRIPT}; sp_discover_config")

    assert result.returncode == 47
    stderr = result.stderr
    assert f"config-missing installer-config.yml at {env['SP_CONFIG_MOUNT_POINT']}/installer-config.yml" in stderr
    assert "Entering rescue mode" in stderr
    assert "source=sysfs" in stderr
    assert "source=proc/partitions" in stderr
    assert "source=by-label" in stderr
    assert "blkid" not in stderr
    assert "lsblk" not in stderr
    assert shell_log.exists()
    assert "rescue-shell" in shell_log.read_text()


def test_nonremovable_media_triggers_fatal(tmp_path: Path) -> None:
    label_device = _create_block(tmp_path, "bad-disk")
    _populate_config_media(label_device)

    label_dir = tmp_path / "by-label"
    label_dir.mkdir(parents=True, exist_ok=True)
    (label_dir / "SP_CONFIG").symlink_to(label_device)

    env = _base_env(tmp_path)
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

    result = _run_command(env, f". {SCRIPT}; sp_discover_config")

    assert result.returncode == 47
    stderr = result.stderr
    assert "config-media-not-removable" in stderr
    assert "rescue-shell" in shell_log.read_text()


def test_payload_missing_os_dir_triggers_fatal(tmp_path: Path) -> None:
    partition_device = _create_partition(tmp_path, "missing-os", "missing-os1", removable="1")
    (partition_device / "installer-config.yml").write_text("config\n")

    env = _base_env(tmp_path)
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

    result = _run_command(env, f". {SCRIPT}; sp_discover_config")

    assert result.returncode == 47
    stderr = result.stderr
    assert f"payload-missing os/ at {env['SP_CONFIG_MOUNT_POINT']}/os" in stderr


def test_payload_ambiguous_tarballs(tmp_path: Path) -> None:
    partition_device = _create_partition(tmp_path, "ambiguous", "ambiguous1", removable="1")
    _populate_config_media(
        partition_device,
        "ambiguous\n",
        rootfs_names=("rootfs.tar.gz", "rootfs.tar.zst"),
    )

    env = _base_env(tmp_path)
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

    result = _run_command(env, f". {SCRIPT}; sp_discover_config")

    assert result.returncode == 47
    stderr = result.stderr
    assert f"payload-ambiguous found=2 in {env['SP_CONFIG_MOUNT_POINT']}/os" in stderr


def test_uses_heuristic_partition_names(tmp_path: Path) -> None:
    sys_block = tmp_path / "sys" / "block"
    dev_root = tmp_path / "dev"
    sys_block.mkdir(parents=True, exist_ok=True)
    dev_root.mkdir(parents=True, exist_ok=True)
    block_dir = sys_block / "sda"
    block_dir.mkdir(exist_ok=True)
    (block_dir / "removable").write_text("1")
    partition_device = dev_root / "sda1"
    partition_device.mkdir(exist_ok=True)
    _populate_config_media(partition_device, "heuristic\n")

    env = _base_env(tmp_path)
    env["SP_CONFIG_SCAN_REMOVABLE_FALLBACK"] = "0"

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
        assert "blkid" not in text, f"blkid reference found in {path}"
        assert "lsblk" not in text, f"lsblk reference found in {path}"
