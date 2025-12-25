"""Ensure VFAT capability probing unmasks missing support before discovery."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INIT_SCRIPT = Path("installer/init/init.sh")


def _run_installer(env_overrides: dict[str, str]) -> subprocess.CompletedProcess:
    env = os.environ.copy()
    env.update(env_overrides)
    env.setdefault("SP_INIT_SCRIPT_PATH", str((ROOT / INIT_SCRIPT).resolve()))
    env.setdefault(
        "SP_RUNTIME_LIB_DIR",
        str((ROOT / "installer" / "runtime" / "lib").resolve()),
    )
    env["SP_SKIP_INIT_MAIN"] = "1"

    command = f'. "{INIT_SCRIPT}"; sp_run_installer'
    return subprocess.run(
        ["bash", "-c", command],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
    )


def test_missing_vfat_support_enters_rescue(tmp_path: Path) -> None:
    stub_bin = tmp_path / "bin"
    stub_bin.mkdir(parents=True, exist_ok=True)

    mount_stub = stub_bin / "mount"
    mount_stub.write_text("#!/bin/sh\nexit 22\n")
    mount_stub.chmod(0o755)

    lib_modules = Path("/lib/modules")
    expected_version = ""
    if lib_modules.is_dir():
        versions = sorted(
            entry.name for entry in lib_modules.iterdir() if entry.is_dir()
        )
        if versions:
            expected_version = versions[0]

    log_path = tmp_path / "installer.log"
    log_path.write_text("", encoding="utf-8")

    env = {
        "PATH": f"{stub_bin}{os.pathsep}{os.environ.get('PATH', '')}",
        "SP_LOG_DEVICE": str(log_path),
        "SP_RESCUE_NONINTERACTIVE": "1",
    }
    if expected_version:
        env["SP_EXPECTED_KERNEL_VERSION"] = expected_version

    result = _run_installer(env)

    assert result.returncode == 1, result.stderr
    log_text = log_path.read_text()

    assert "[SP-INSTALLER][FATAL] VFAT mount test failed" in log_text
    assert "rescue-reason=missing-vfat-support" in log_text
    assert "state=discover-config" not in log_text
