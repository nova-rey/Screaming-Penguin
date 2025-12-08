"""Tests that the disk layout planner produces a deterministic plan."""

from __future__ import annotations

import json
import os
import subprocess
import textwrap
from pathlib import Path

INSTALLER_DISK_LAYOUT_SH = Path("installer/runtime/lib/disk_layout.sh")


def _write_config(tmp_path: Path, contents: str) -> Path:
    config_path = tmp_path / "installer-config.yml"
    config_path.write_text(textwrap.dedent(contents).strip() + "\n")
    return config_path


def _run_planner(
    tmp_path: Path,
    config: str,
    extra_env: dict[str, str] | None = None,
    test_disk_bytes: int | None = 107_374_182_400,
) -> subprocess.CompletedProcess:
    config_path = _write_config(tmp_path, config)
    env = os.environ.copy()
    env["SP_CONFIG_PATH"] = str(config_path)
    env["SP_DISK_LAYOUT_ASSUME_TARGET_BLOCK"] = "1"

    if test_disk_bytes is not None:
        env["SP_DISK_LAYOUT_TEST_DISK_SIZE_BYTES"] = str(test_disk_bytes)

    if extra_env:
        env.update(extra_env)

    return subprocess.run(
        ["/bin/sh", "-c", f". {INSTALLER_DISK_LAYOUT_SH} && sp_print_layout_plan"],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def test_planner_outputs_efi_and_root(tmp_path: Path) -> None:
    config = """
    installer:
      write_gate: true
    target:
      disk: fake-disk
    """

    result = _run_planner(tmp_path, config)

    assert result.returncode == 0, result.stderr

    plan = json.loads(result.stdout)
    assert plan["target_disk"] == "/dev/fake-disk"
    assert plan["table"] == "gpt"
    assert len(plan["partitions"]) == 2

    efi = plan["partitions"][0]
    assert efi["role"] == "efi"
    assert efi["filesystem"] == "fat32"
    assert efi["size_mib"] == 512
    assert efi["start_mib"] == 1

    root = plan["partitions"][1]
    assert root["role"] == "root"
    assert root["filesystem"] == "ext4"
    assert root["size_mib"] == 101_883
    assert root["start_mib"] == 513


def test_planner_accepts_layout_overrides(tmp_path: Path) -> None:
    config = """
    installer:
      write_gate: true
      disk_layout:
        efi_size_mib: 1024
        efi_alignment_mib: 2
        root_alignment_mib: 4
        root_reserved_mib: 8
    target:
      disk: fake-disk
    """

    result = _run_planner(tmp_path, config)

    assert result.returncode == 0, result.stderr

    plan = json.loads(result.stdout)
    efi = plan["partitions"][0]
    assert efi["size_mib"] == 1024
    assert efi["start_mib"] == 2

    root = plan["partitions"][1]
    assert root["start_mib"] == 1028  # align up to 4 MiB boundary
    assert root["size_mib"] == 101_364


def test_planner_fails_without_target_disk(tmp_path: Path) -> None:
    config = """
    installer:
      write_gate: true
    """

    result = _run_planner(tmp_path, config)

    assert result.returncode != 0
    assert "target disk not configured" in result.stderr


def test_planner_requires_disk_size(tmp_path: Path) -> None:
    config = """
    installer:
      write_gate: true
    target:
      disk: fake-disk
    """

    missing_size = tmp_path / "missing-size"
    result = _run_planner(
        tmp_path,
        config,
        extra_env={
            "SP_DISK_LAYOUT_SIZE_OVERRIDE_PATH": str(missing_size),
        },
        test_disk_bytes=None,
    )

    assert result.returncode != 0
    assert "could not read size" in result.stderr
