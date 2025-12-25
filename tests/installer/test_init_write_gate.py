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

    modules_root = Path("/lib/modules")
    available_versions = []
    if modules_root.is_dir():
        available_versions = sorted(
            entry.name
            for entry in modules_root.iterdir()
            if entry.is_dir()
        )
    if "SP_EXPECTED_KERNEL_VERSION" not in env and available_versions:
        env["SP_EXPECTED_KERNEL_VERSION"] = available_versions[0]

    if available_versions:
        modules_override_root = tmp_path / "modules"
        modules_override_root.mkdir(exist_ok=True)
        uname_proc = subprocess.run(
            ["uname", "-r"],
            capture_output=True,
            text=True,
            check=False,
        )
        runtime_kernel = uname_proc.stdout.strip()
        if runtime_kernel:
            target = modules_override_root / runtime_kernel
            target.symlink_to(modules_root / available_versions[0])
            env["SP_INSTALLER_MODULES_ROOT"] = str(modules_override_root)

    fake_bin = tmp_path / "bin"
    fake_bin.mkdir(exist_ok=True)
    mount_stub = fake_bin / "mount"
    mount_stub.write_text(
        textwrap.dedent(
            """\
            #!/bin/sh
            if [ "$1" = "-t" ] && [ "$2" = "vfat" ]; then
                exit 0
            fi

            exec /bin/mount "$@"
            """
        )
    )
    mount_stub.chmod(0o755)
    env["PATH"] = str(fake_bin) + os.pathsep + env.get("PATH", "")
    env["SP_PREPEND_PATH"] = str(fake_bin)

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
