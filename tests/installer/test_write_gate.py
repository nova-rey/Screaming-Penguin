"""Tests for the installer write-gate Python helper."""

import textwrap
from pathlib import Path

import pytest

from installer.python.write_gate import WriteGateError, validate_write_gate


def _write_config(tmp_path: Path, contents: str) -> Path:
    config_path = tmp_path / "installer-config.yml"
    config_path.write_text(textwrap.dedent(contents).strip() + "\n")
    return config_path


def test_missing_write_gate_field(tmp_path: Path) -> None:
    config = _write_config(
        tmp_path,
        """
        installer:
          foo: bar
        """,
    )

    with pytest.raises(WriteGateError, match="write_gate missing"):
        validate_write_gate(config)


def test_write_gate_disabled(tmp_path: Path) -> None:
    config = _write_config(
        tmp_path,
        """
        installer:
          write_gate: false
        """,
    )

    with pytest.raises(WriteGateError, match="is false"):
        validate_write_gate(config)


def test_write_gate_enabled(tmp_path: Path) -> None:
    config = _write_config(
        tmp_path,
        """
        installer:
          write_gate: true
        """,
    )

    assert validate_write_gate(config) is True
