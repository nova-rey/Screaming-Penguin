"""Rescue mode must keep PID 1 alive by restarting the shell."""

from __future__ import annotations

import os
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEST_BIN = Path("tests/installer/bin")
INIT_SCRIPT = Path("installer/init/init.sh")


def _run_rescue_process(env_overrides: dict[str, str]) -> subprocess.Popen:
    env = os.environ.copy()
    env.update(env_overrides)
    env["PATH"] = f"{TEST_BIN}{os.pathsep}{env.get('PATH', '')}"

    env.setdefault("SP_INIT_SCRIPT_PATH", str((ROOT / INIT_SCRIPT).resolve()))
    env.setdefault(
        "SP_RUNTIME_LIB_DIR",
        str((ROOT / "installer" / "runtime" / "lib").resolve()),
    )
    env["SP_SKIP_INIT_MAIN"] = "1"

    command = '. installer/init/init.sh; sp_enter_rescue_mode "test"'
    return subprocess.Popen(
        ["bash", "-c", command],
        cwd=ROOT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def test_rescue_shell_restarts(tmp_path: Path) -> None:
    console = tmp_path / "console"
    console.write_text("", encoding="utf-8")
    shell_log = tmp_path / "rescue-shell.log"
    label_log = tmp_path / "rescue-log.txt"

    env = {
        "SP_TEST_RESCUE_SHELL": str(
            (ROOT / "tests" / "installer" / "bin" / "rescue-shell").resolve()
        ),
        "SP_TEST_RESCUE_SHELL_EXIT": "5",
        "SP_TEST_RESCUE_SHELL_LOG": str(shell_log),
        "SP_TEST_RESCUE_CONSOLE": str(console),
        "SP_RESCUE_LOG_DEVICE": str(label_log),
        "SP_LOG_DEVICE": str(label_log),
    }

    proc = _run_rescue_process(env)

    try:
        deadline = time.time() + 3
        while time.time() < deadline:
            if shell_log.exists():
                lines = shell_log.read_text().splitlines()
                if lines.count("rescue-shell") >= 2:
                    break
            time.sleep(0.1)
        else:
            raise AssertionError("Rescue shell did not restart within deadline")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=1)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=1)

    assert label_log.exists()
    log_text = label_log.read_text()
    assert "note=shell-exited" in log_text
    assert "note=launching-shell" in log_text
    assert shell_log.read_text().count("rescue-shell") >= 2
