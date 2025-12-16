"""BusyBox-only config discovery tests."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path("installer/runtime/lib/config_discovery.sh")
TEST_BIN = Path("tests/installer/bin")


def _run_command(env_overrides: dict[str, str], command: str) -> subprocess.CompletedProcess:
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


def _setup_layout(tmp_path: Path) -> tuple[Path, Path, Path, Path]:
    sys_block = tmp_path / "sys" / "block"
    dev_root = tmp_path / "dev"
    proc_root = tmp_path / "proc"
    mount_point = tmp_path / "config"
    sys_block.mkdir(parents=True, exist_ok=True)
    dev_root.mkdir(parents=True, exist_ok=True)
    proc_root.mkdir(parents=True, exist_ok=True)
    mount_point.mkdir(parents=True, exist_ok=True)
    return sys_block, dev_root, proc_root, mount_point


def _create_base_device(sys_block: Path, name: str) -> Path:
    base = sys_block / name
    base.mkdir(parents=True, exist_ok=True)
    return base


def _create_partition_device(dev_root: Path, name: str, content: str) -> Path:
    device = dev_root / name
    device.mkdir(parents=True, exist_ok=True)
    (device / "installer-config.yml").write_text(content)
    os_dir = device / "os"
    os_dir.mkdir(parents=True, exist_ok=True)
    return device


def _write_proc_partitions(proc_root: Path, names: list[str]) -> None:
    lines = ["major minor  #blocks  name"]
    blocks = 123456
    minor = 0
    for name in names:
        lines.append(f"   8        {minor}  {blocks} {name}")
        minor += 1
        blocks += 100
    (proc_root / "partitions").write_text("\n".join(lines) + "\n")


def _write_blkid_map(map_path: Path, mapping: dict[str, list[str]]) -> None:
    entries: list[str] = []
    for device, lines in mapping.items():
        entries.append(device)
        entries.extend(lines)
        entries.append("")
    map_path.write_text("\n".join(entries))


def _base_env(
    sys_block: Path,
    dev_root: Path,
    proc_root: Path,
    mount_point: Path,
    blkid_map: Path,
) -> dict[str, str]:
    return {
        "SP_SYS_BLOCK_ROOT": str(sys_block),
        "SP_DEV_ROOT": str(dev_root),
        "SP_PROC_ROOT": str(proc_root),
        "SP_CONFIG_MOUNTPOINT": str(mount_point),
        "SP_TEST_BLKID_MAP": str(blkid_map),
    }


def _assert_config_found(
    result: subprocess.CompletedProcess, expected_content: str, mount_point: Path
) -> None:
    assert result.returncode == 0, result.stderr
    lines = result.stdout.strip().splitlines()
    assert lines[0] == str(mount_point / "installer-config.yml")
    assert lines[1] == str(mount_point)
    assert (mount_point / "installer-config.yml").read_text() == expected_content


def _with_blkid_mapping(tmp_path: Path, mapping: dict[str, list[str]]) -> Path:
    map_path = tmp_path / "blkid-map"
    _write_blkid_map(map_path, mapping)
    return map_path


def test_probe_label_without_by_label_dir(tmp_path: Path) -> None:
    sys_block, dev_root, proc_root, mount_point = _setup_layout(tmp_path)
    _create_base_device(sys_block, "diskA")
    device_path = _create_partition_device(dev_root, "diskA1", "config\n")
    _write_proc_partitions(proc_root, ["diskA", "diskA1"])
    device_path_str = str(device_path)
    blkid_map = _with_blkid_mapping(
        tmp_path,
        {
            device_path_str: [f"DEVNAME={device_path_str}", "LABEL=SP_CONFIG"],
        },
    )

    env = _base_env(sys_block, dev_root, proc_root, mount_point, blkid_map)
    command = (
        f'. {SCRIPT}; '
        'if sp_discover_config; then '
        'printf \'%s\\n%s\\n\' "$SP_CONFIG_PATH" "$CONFIG_MOUNT"; '
        'fi'
    )
    result = _run_command(env, command)

    _assert_config_found(result, "config\n", mount_point)
    stderr = result.stderr
    assert "config-resolver=probe-label" in stderr
    assert f"config-dev={device_path_str}" in stderr
    assert "payload-dir=" in stderr


def test_probe_label_prefers_labeled_partition(tmp_path: Path) -> None:
    sys_block, dev_root, proc_root, mount_point = _setup_layout(tmp_path)
    _create_base_device(sys_block, "diskA")
    _create_base_device(sys_block, "diskB")
    device_path_a = str(_create_partition_device(dev_root, "diskA1", "first\n"))
    device_path_b = str(_create_partition_device(dev_root, "diskB1", "second\n"))
    _write_proc_partitions(proc_root, ["diskA", "diskA1", "diskB", "diskB1"])
    blkid_map = _with_blkid_mapping(
        tmp_path,
        {
            device_path_a: [f"DEVNAME={device_path_a}", "LABEL=OTHER"],
            device_path_b: [f"DEVNAME={device_path_b}", "LABEL=SP_CONFIG"],
        },
    )

    env = _base_env(sys_block, dev_root, proc_root, mount_point, blkid_map)
    command = (
        f'. {SCRIPT}; '
        'if sp_discover_config; then '
        'printf \'%s\\n%s\\n\' "$SP_CONFIG_PATH" "$CONFIG_MOUNT"; '
        'fi'
    )
    result = _run_command(env, command)

    _assert_config_found(result, "second\n", mount_point)
    stderr = result.stderr
    assert "config-resolver=probe-label" in stderr
    assert f"config-dev={device_path_b}" in stderr
    assert "phase=probe-label" in stderr
    assert "/dev/diskB1 result=match" in stderr


def test_label_not_found_triggers_rescue(tmp_path: Path) -> None:
    sys_block, dev_root, proc_root, mount_point = _setup_layout(tmp_path)
    _create_base_device(sys_block, "diskA")
    _create_base_device(sys_block, "diskB")
    device_path_a = str(_create_partition_device(dev_root, "diskA1", "retry\n"))
    device_path_b = str(_create_partition_device(dev_root, "diskB1", "retry\n"))
    _write_proc_partitions(proc_root, ["diskA", "diskA1", "diskB", "diskB1"])
    blkid_map = _with_blkid_mapping(
        tmp_path,
        {
            device_path_a: [f"DEVNAME={device_path_a}", "LABEL=OTHER"],
            device_path_b: [f"DEVNAME={device_path_b}", "LABEL=OTHER"],
        },
    )

    env = _base_env(sys_block, dev_root, proc_root, mount_point, blkid_map)
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
    assert "config-label-not-found label=SP_CONFIG candidates=2" in stderr


def test_runtime_has_no_lsblk_or_udevadm_references() -> None:
    runtime_dir = ROOT / "installer" / "runtime"
    for path in runtime_dir.rglob("*"):
        if not path.is_file():
            continue
        text = path.read_text(errors="ignore")
        assert "lsblk" not in text, f"lsblk reference found in {path}"
        assert "udevadm" not in text, f"udevadm reference found in {path}"
