#!/usr/bin/env bash
set -euo pipefail

required_commands=(blkid lsblk)
missing=()
for tool in "${required_commands[@]}"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    missing+=("$tool")
  fi
done

if (( ${#missing[@]} )); then
  echo "[sanity_checks] ERROR: missing required commands: ${missing[*]}" >&2
  exit 1
fi

echo "[sanity_checks] All required commands are available."
if [[ "${OUROBOROS_ENABLE_DESTRUCTIVE:-0}" != "1" ]]; then
  echo "[sanity_checks] Running in dry-run mode by default. Set OUROBOROS_ENABLE_DESTRUCTIVE=1 + confirmation to allow writes."
else
  echo "[sanity_checks] Destructive mode requested, but commands still gated until confirmed." >&2
fi
