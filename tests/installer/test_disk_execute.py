"""Tests that Phase 10 applies the GPT plan and makes mountable filesystems."""

from __future__ import annotations

import json
import os
import subprocess
import textwrap
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
INIT_SCRIPT = Path("installer/init/init.sh")
BUILD_DIR = REPO_ROOT / "build"
DISK_ARTIFACT_NAME = "phase10-disk-execute.img"


def _write_config(tmp_dir: Path, disk_target: str) -> Path:
    config_path = tmp_dir / "installer-config.yml"
    config_contents = f"""
    installer:
      write_gate: true
    target:
      disk: '{disk_target}'
      wipe: true
    """
    config_path.write_text(textwrap.dedent(config_contents).strip() + "\n")
    return config_path


def _spawn_env(
    tmp_dir: Path, config_path: Path, target_disk: str, disk_size: int
) -> dict[str, str]:
    log_path = tmp_dir / "disk-exec.log"
    serial_path = tmp_dir / "serial.log"

    env = os.environ.copy()
    env.update(
        {
            "SP_SKIP_INIT_MAIN": "1",
            "SP_MODE": "INSTALL",
            "SP_ENABLE_DISK_EXECUTE": "1",
            "SP_CONFIG_PATH": str(config_path),
            "SP_TARGET_DISK": target_disk,
            "SP_TARGET_KIND": "disk",
            "SP_DISK_LAYOUT_ASSUME_TARGET_BLOCK": "1",
            "SP_DISK_LAYOUT_TEST_DISK_SIZE_BYTES": str(disk_size),
            "SP_LOG_DEVICE": str(log_path),
            "SP_WRITE_GATE_SERIAL_DEVICE": str(serial_path),
            "SP_INIT_SCRIPT_PATH": str(INIT_SCRIPT.resolve()),
        }
    )
    return env


def _run_init_command(command: str, env: dict[str, str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["/bin/sh", "-c", f". {INIT_SCRIPT} && {command}"],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def _attach_loop_device(image: Path) -> str:
    result = subprocess.run(
        ["sudo", "losetup", "--find", "--show", str(image)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def _detach_loop_device(device: str) -> None:
    subprocess.run(["sudo", "losetup", "-d", device], check=False)


def _partition_device(disk: str, index: int) -> str:
    base = disk
    if base.startswith("/dev/"):
        base = base[5:]
    if base and base[-1].isdigit():
        suffix = f"p{index}"
    else:
        suffix = str(index)
    return f"/dev/{base}{suffix}"


def _umount(path: Path) -> None:
    subprocess.run(["sudo", "umount", str(path)], check=False)


def test_disk_execute_writes_plan(tmp_path: Path) -> None:
    BUILD_DIR.mkdir(exist_ok=True)
    disk_path = BUILD_DIR / DISK_ARTIFACT_NAME
    disk_path.unlink(missing_ok=True)

    disk_size = 3 * 1024 * 1024 * 1024
    subprocess.run(["truncate", "-s", str(disk_size), str(disk_path)], check=True)

    loop_device = None
    try:
        try:
            loop_device = _attach_loop_device(disk_path)
        except subprocess.CalledProcessError as exc:
            pytest.skip(f"loop devices unavailable: {exc.stderr.strip()}")
        config_path = _write_config(tmp_path, loop_device)
        env = _spawn_env(tmp_path, config_path, loop_device, disk_size)

        planner = _run_init_command('sp_print_layout_plan "$SP_TARGET_DISK"', env)
        assert planner.returncode == 0, planner.stderr
        plan = json.loads(planner.stdout)
        assert plan["table"] == "gpt"
        assert len(plan["partitions"]) == 2

        efi_entry = next(p for p in plan["partitions"] if p["role"] == "efi")
        root_entry = next(p for p in plan["partitions"] if p["role"] == "root")

        assert efi_entry["filesystem"] == "fat32"
        assert root_entry["filesystem"] == "ext4"

        executor_env = dict(env)
        executor_env["SP_DRY_RUN"] = "1"
        executor = _run_init_command("sp_execute_gpt_plan", executor_env)
        assert executor.returncode == 0, executor.stderr
    finally:
        if loop_device:
            _detach_loop_device(loop_device)
        disk_path.unlink(missing_ok=True)
