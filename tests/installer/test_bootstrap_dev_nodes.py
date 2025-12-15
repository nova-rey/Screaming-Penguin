"""Verify bootstrap device helpers run BusyBox mdev before config discovery."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INIT_SCRIPT = Path("installer/init/init.sh")
TEST_BIN = Path("tests/installer/bin")


def _run_command(
    env_overrides: dict[str, str], command: str
) -> subprocess.CompletedProcess:
    env = os.environ.copy()
    env.update(env_overrides)
    env["PATH"] = f"{TEST_BIN}{os.pathsep}{env.get('PATH', '')}"
    env.setdefault("SP_INIT_SCRIPT_PATH", str((ROOT / INIT_SCRIPT).resolve()))
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


def _create_block(tmp_path: Path, name: str) -> Path:
    sys_block, dev_root = _setup_sys_dev(tmp_path)
    block_dir = sys_block / name
    block_dir.mkdir(exist_ok=True)
    (dev_root / name).mkdir(exist_ok=True)
    return block_dir


def _create_partition(tmp_path: Path, parent: str, partition: str) -> Path:
    sys_block, dev_root = _setup_sys_dev(tmp_path)
    parent_dir = sys_block / parent
    parent_dir.mkdir(parents=True, exist_ok=True)
    partition_dir = parent_dir / partition
    partition_dir.mkdir(parents=True, exist_ok=True)
    device = dev_root / partition
    device.mkdir(exist_ok=True)
    return device


def test_bootstrap_runs_mdev_before_config_discovery(tmp_path: Path) -> None:
    _create_block(tmp_path, "sda")
    partition = _create_partition(tmp_path, "sda", "sda1")
    (partition / "installer-config.yml").write_text("bootstrap\n")

    mount_point = tmp_path / "config"
    mount_point.mkdir(exist_ok=True)
    log = tmp_path / "installer.log"
    mdev_log = tmp_path / "mdev.log"
    label_dir = tmp_path / "by-label"
    label_dir.mkdir(parents=True, exist_ok=True)

    env = {
        "SP_SYS_BLOCK_ROOT": str((tmp_path / "sys" / "block").resolve()),
        "SP_DEV_ROOT": str((tmp_path / "dev").resolve()),
        "SP_CONFIG_LABEL_DIR": str((tmp_path / "by-label").resolve()),
        "SP_CONFIG_MOUNT_POINT": str(mount_point),
        "SP_CONFIG_DISCOVERY_MAX_ATTEMPTS": "1",
        "SP_LOG_DEVICE": str(log),
        "SP_TEST_MDEV_LOG": str(mdev_log),
    }

    command = (
        f". {INIT_SCRIPT}; "
        "sp_bootstrap; "
        "if sp_discover_config; then "
        'printf "%s\\n%s\\n" "$SP_CONFIG_PATH" "$CONFIG_MOUNT"; '
        "fi"
    )

    result = _run_command(env, command)

    assert result.returncode == 0, result.stderr
    assert "state=dev-bootstrap" in result.stderr
    assert "state=discover-config" in result.stderr
    assert result.stderr.find("state=dev-bootstrap") < result.stderr.find(
        "state=discover-config"
    )
    assert "installer-config.yml" in result.stdout
    assert mdev_log.exists()
    assert "mdev-args=-s" in mdev_log.read_text()
