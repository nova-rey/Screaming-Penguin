"""Verify bootstrap device helpers run BusyBox mdev before config discovery."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
INIT_SCRIPT = Path("installer/init/init.sh")
TEST_BIN = Path("tests/installer/bin")
DEFAULT_CMD_TIMEOUT_SECONDS = int(os.environ.get("SP_TEST_CMD_TIMEOUT_SECONDS", "10"))


def _run_command(
    env_overrides: dict[str, str], command: str, timeout_seconds: int | None = None
) -> subprocess.CompletedProcess:
    env = os.environ.copy()
    env.update(env_overrides)
    extra_path_prefix = env.pop("SP_TEST_EXTRA_PATH", None)
    base_path = env.get("PATH") or os.environ.get("PATH", "")

    path_parts: list[str] = []
    if extra_path_prefix:
        path_parts.append(extra_path_prefix)
    path_parts.append(str(TEST_BIN))
    if base_path:
        path_parts.append(base_path)
    env["PATH"] = os.pathsep.join(path_parts)

    env.setdefault("SP_INIT_SCRIPT_PATH", str((ROOT / INIT_SCRIPT).resolve()))
    env.setdefault(
        "SP_RUNTIME_LIB_DIR",
        str((ROOT / "installer" / "runtime" / "lib").resolve()),
    )

    timeout = (
        DEFAULT_CMD_TIMEOUT_SECONDS if timeout_seconds is None else timeout_seconds
    )
    try:
        return subprocess.run(
            ["bash", "-c", command],
            cwd=ROOT,
            env=env,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        stdout = (exc.stdout or "").strip()
        stderr = (exc.stderr or "").strip()
        pytest.fail(
            f"Command timed out after {timeout}s: {command}\n"
            f"stdout:\n{stdout}\n\nstderr:\n{stderr}"
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

    kernel_release = subprocess.run(
        ["uname", "-r"], capture_output=True, text=True, check=True
    ).stdout.strip()
    modules_root = tmp_path / "modules"
    modules_root.mkdir(parents=True, exist_ok=True)
    (modules_root / kernel_release).mkdir(parents=True, exist_ok=True)
    env["SP_INSTALLER_MODULES_ROOT"] = str(modules_root)

    stub_bin = tmp_path / "bin"
    stub_bin.mkdir(parents=True, exist_ok=True)
    calls_log = tmp_path / "mdev-calls.log"

    mdev_stub = stub_bin / "mdev"
    mdev_stub.write_text(
        "#!/bin/sh\n"
        'log="${SP_TEST_MDEV_LOG:-/tmp/mdev.log}"\n'
        'printf \'mdev-args=%s\\n\' "$*" >>"$log" 2>/dev/null || true\n'
        f'echo "mdev $@" >> "{calls_log}"\n'
        "exit 0\n"
    )
    mdev_stub.chmod(0o755)

    sbin_dir = tmp_path / "sbin"
    sbin_dir.mkdir(parents=True, exist_ok=True)
    (sbin_dir / "mdev").symlink_to(mdev_stub)

    env.update(
        {
            "SP_TEST_EXTRA_PATH": os.pathsep.join([str(stub_bin), str(sbin_dir)]),
            "SP_BOOTSTRAP_MDEV_BIN": str(mdev_stub),
        }
    )

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
    assert calls_log.exists()
    assert "mdev -s" in calls_log.read_text()


def test_storage_bootstrap_detects_emmc(tmp_path: Path) -> None:
    sys_block, dev_root = _setup_sys_dev(tmp_path)
    mmc_dev = sys_block / "mmcblk0"
    mmc_dev.mkdir(exist_ok=True)
    (mmc_dev / "size").write_text("0\n")
    (mmc_dev / "removable").write_text("0\n")
    (dev_root / "mmcblk0").mkdir(exist_ok=True)

    log = tmp_path / "storage-bootstrap.log"

    kernel_release = subprocess.run(
        ["uname", "-r"], capture_output=True, text=True, check=True
    ).stdout.strip()
    modules_root = tmp_path / "modules"
    modules_root.mkdir(parents=True, exist_ok=True)
    (modules_root / kernel_release).mkdir(parents=True, exist_ok=True)

    stub_bin = tmp_path / "bin"
    stub_bin.mkdir(parents=True, exist_ok=True)
    mdev_stub = stub_bin / "mdev"
    mdev_stub.write_text("#!/bin/sh\nexit 0\n")
    mdev_stub.chmod(0o755)

    sbin_dir = tmp_path / "sbin"
    sbin_dir.mkdir(parents=True, exist_ok=True)
    (sbin_dir / "mdev").symlink_to(mdev_stub)

    env = {
        "SP_SYS_BLOCK_ROOT": str(sys_block.resolve()),
        "SP_DEV_ROOT": str(dev_root.resolve()),
        "SP_INSTALLER_MODULES_ROOT": str(modules_root.resolve()),
        "SP_LOG_DEVICE": str(log),
        "SP_TEST_EXTRA_PATH": os.pathsep.join([str(stub_bin), str(sbin_dir)]),
        "SP_BOOTSTRAP_MDEV_BIN": str(mdev_stub),
    }

    command = f". {INIT_SCRIPT}; sp_bootstrap"

    result = _run_command(env, command)

    assert result.returncode == 0, result.stderr
    assert "storage-platform=emmc" in result.stdout
    assert "mmc-sys=" in result.stdout
    assert "mmcblk0" in result.stdout

    fatal_marker = "[SP-INSTALLER][FATAL] no-block-devices-after-storage-bootstrap"
    log_contents = log.read_text() if log.exists() else ""
    assert fatal_marker not in result.stdout
    assert fatal_marker not in log_contents
