from __future__ import annotations

import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
INIT_SCRIPT = Path("installer/init/init.sh")
COMMAND_TIMEOUT_SECONDS = int(os.environ.get("SP_TEST_CMD_TIMEOUT_SECONDS", "20"))


def _run_helper_command(env: dict[str, str], command: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", "-c", command],
        cwd=str(ROOT),
        env=env,
        capture_output=True,
        text=True,
        timeout=COMMAND_TIMEOUT_SECONDS,
    )


def _base_environment() -> dict[str, str]:
    env = os.environ.copy()
    env.setdefault("SP_INIT_SCRIPT_PATH", str((ROOT / INIT_SCRIPT).resolve()))
    env.setdefault(
        "SP_RUNTIME_LIB_DIR",
        str((ROOT / "installer" / "runtime" / "lib").resolve()),
    )
    env["SP_RESCUE_NONINTERACTIVE"] = "1"
    env["PATH"] = os.environ.get("PATH", "")
    return env


def test_bootstrap_populates_by_label_symlinks(tmp_path: Path) -> None:
    dev_root = tmp_path / "dev-root"
    label_dir = dev_root / "disk" / "by-label"
    log_file = tmp_path / "populate.log"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir(parents=True)
    blkid_stub = bin_dir / "blkid"
    blkid_stub.write_text(
        "#!/bin/sh\n"
        "cat <<'EOF'\n"
        "DEVNAME=/dev/sda1\n"
        "LABEL=SP_CONFIG\n"
        "\n"
        "DEVNAME=/dev/sda2\n"
        "LABEL=SP_BOOT\n"
        "EOF\n"
    )
    blkid_stub.chmod(0o755)

    log_file.write_text("", encoding="utf-8")
    env = _base_environment()
    env.update(
        {
            "SP_DEV_ROOT": str(dev_root),
            "SP_CONFIG_LABEL_DIR": str(label_dir),
            "SP_LOG_DEVICE": str(log_file),
            "PATH": f"{str(bin_dir)}{os.pathsep}{env['PATH']}",
        }
    )

    command = ". installer/init/init.sh; sp_populate_by_label_namespace"

    result = _run_helper_command(env, command)

    assert result.returncode == 0, result.stderr
    log_contents = log_file.read_text()
    assert "[SP-INSTALLER][FATAL]" not in log_contents
    assert "[SP-INSTALLER][WARN] no labeled block devices found via blkid; by-label namespace will be empty" not in log_contents

    config_link = label_dir / "SP_CONFIG"
    boot_link = label_dir / "SP_BOOT"
    assert config_link.is_symlink(), f"expected {config_link} to be a symlink"
    assert boot_link.is_symlink(), f"expected {boot_link} to be a symlink"
    assert os.readlink(config_link) == "/dev/sda1"
    assert os.readlink(boot_link) == "/dev/sda2"


def test_missing_blkid_triggers_rescue_reason(tmp_path: Path) -> None:
    dev_root = tmp_path / "dev-root"
    label_dir = dev_root / "disk" / "by-label"
    log_file = tmp_path / "populate.log"

    log_file.write_text("", encoding="utf-8")
    env = _base_environment()
    env.update(
        {
            "SP_DEV_ROOT": str(dev_root),
            "SP_CONFIG_LABEL_DIR": str(label_dir),
            "SP_LOG_DEVICE": str(log_file),
            "SP_BLKID_BIN": "/no-such-bin/blkid",
        }
    )

    command = (
        ". installer/init/init.sh; "
        "sp_populate_by_label_namespace; "
        "rc=$?; "
        'printf "SP_RESCUE_REASON=%s\\n" "${SP_RESCUE_REASON:-}"; '
        "exit $rc"
    )

    result = _run_helper_command(env, command)

    assert result.returncode != 0, "expected helper to fail when blkid is missing"
    assert "SP_RESCUE_REASON=missing-blkid" in result.stdout
    log_contents = log_file.read_text() if log_file.exists() else ""
    assert (
        "[SP-INSTALLER][FATAL] blkid missing; cannot populate by-label namespace"
        in log_contents
    )
