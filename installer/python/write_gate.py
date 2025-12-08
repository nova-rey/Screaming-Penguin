"""Helpers that enforce installer.write_gate semantics."""

from __future__ import annotations

import pathlib
from typing import Any, Mapping, Union

__all__ = ["WriteGateError", "validate_write_gate"]


class WriteGateError(Exception):
    """Raised when the installer write-gate value cannot be satisfied."""


def _load_yaml(path: pathlib.Path) -> Mapping[str, Any]:
    try:
        import yaml  # type: ignore[import]
    except ImportError as exc:  # pragma: no cover - dependent on runtime
        raise WriteGateError("PyYAML is required to read installer-config.yml") from exc

    try:
        contents = path.read_text()
    except OSError as exc:
        raise WriteGateError(f"Could not read config file at {path}") from exc

    try:
        payload = yaml.safe_load(contents)
    except Exception as exc:  # pylint: disable=broad-except
        raise WriteGateError(f"installer-config.yml is malformed: {exc}") from exc

    if payload is None:
        return {}

    if not isinstance(payload, Mapping):
        raise WriteGateError("installer-config.yml must be a mapping at the top level")

    return payload


def validate_write_gate(path: Union[str, pathlib.Path]) -> bool:
    """Ensure installer.write_gate exists, is a bool, and is true."""

    config_path = pathlib.Path(path)
    if not config_path.is_file():
        raise WriteGateError(f"Config file missing: {config_path}")

    payload = _load_yaml(config_path)
    installer_block = payload.get("installer")

    if installer_block is None:
        raise WriteGateError("installer.write_gate missing: 'installer' block absent")

    if not isinstance(installer_block, Mapping):
        raise WriteGateError(
            "installer.write_gate missing: 'installer' must be a mapping"
        )

    if "write_gate" not in installer_block:
        raise WriteGateError("installer.write_gate missing")

    gate_value = installer_block["write_gate"]

    if not isinstance(gate_value, bool):
        raise WriteGateError("installer.write_gate must be a boolean")

    if not gate_value:
        raise WriteGateError("installer.write_gate is false")

    return True
