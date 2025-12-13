#!/bin/sh
set -eu

required_tools="blkid lsblk"
missing=""
for tool in $required_tools; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    missing="$missing $tool"
  fi
done

if [ -n "$missing" ]; then
  missing="${missing# }"
  echo "[sanity_checks] ERROR: missing required commands: $missing" >&2
  exit 1
fi

echo "[sanity_checks] All required commands are available."
if [ "${OUROBOROS_ENABLE_DESTRUCTIVE:-0}" != "1" ]; then
  echo "[sanity_checks] Running in dry-run mode by default. Set OUROBOROS_ENABLE_DESTRUCTIVE=1 + confirmation to allow writes."
else
  echo "[sanity_checks] Destructive mode requested, but commands still gated until confirmed." >&2
fi
