"""Tests that the init shim enforces the write gate."""

from __future__ import annotations

import os
import subprocess
import textwrap
from pathlib import Path

INSTALL_SCRIPT = Path("installer/init/init.sh")


def _run_init(
    tmp_path: Path, config: str
) -> tuple[subprocess.CompletedProcess, Path, Path]:
    config_path = tmp_path / "installer-config.yml"
    config_path.write_text(textwrap.dedent(config).strip() + "\n")

    console_log = tmp_path / "console.log"
    console_log.write_text("")
    serial_log = tmp_path / "serial.log"
    serial_log.write_text("")

    env = os.environ.copy()
    env["SP_CONFIG_PATH"] = str(config_path)
    env["SP_SKIP_CONFIG_DISCOVERY"] = "1"
    env["SP_EXIT_AFTER_INIT"] = "1"
    env["SP_LOG_DEVICE"] = str(console_log)
    env["SP_WRITE_GATE_SERIAL_DEVICE"] = str(serial_log)

    if "SP_EXPECTED_KERNEL_VERSION" not in env:
        modules_root = Path("/lib/modules")
        if modules_root.is_dir():
            versions = sorted(
                entry.name
                for entry in modules_root.iterdir()
                if entry.is_dir()
            )
            if versions:
                env["SP_EXPECTED_KERNEL_VERSION"] = versions[0]

    result = subprocess.run(
        [str(INSTALL_SCRIPT)],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    return result, console_log, serial_log


def test_init_exits_when_write_gate_missing(tmp_path: Path) -> None:
    result, console_log, serial_log = _run_init(
        tmp_path,
        """
        installer:
        target_disk: /dev/null
        """,
    )

    assert result.returncode != 0
    console_content = console_log.read_text()
    serial_content = serial_log.read_text()

    assert "[SP-INSTALLER] write-gate BLOCKED" in console_content
    assert "write-gate BLOCKED reason=" in serial_content


def test_init_exits_when_write_gate_false(tmp_path: Path) -> None:
    result, console_log, serial_log = _run_init(
        tmp_path,
        """
        installer:
          write_gate: false
        target_disk: /dev/null
        """,
    )

    assert result.returncode != 0
    assert "[SP-INSTALLER] write-gate BLOCKED" in console_log.read_text()
    assert "write-gate BLOCKED reason=" in serial_log.read_text()


def test_init_allows_true_write_gate(tmp_path: Path) -> None:
    result, console_log, serial_log = _run_init(
        tmp_path,
        """
        installer:
          write_gate: true
        target_disk: /dev/null
        """,
    )

    assert result.returncode == 0
    assert "[SP-INSTALLER] write-gate OK" in console_log.read_text()
    assert "[SP-INSTALLER] write-gate OK" in serial_log.read_text()
