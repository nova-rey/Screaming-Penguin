#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

echo "[CI-SMOKE] Running ShellCheck against tools/*.sh..."
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck tools/*.sh
else
  echo "[CI-SMOKE] shellcheck not installed; please install shellcheck or ensure the CI runner provides it."
  exit 1
fi

echo "[CI-SMOKE] Running python3 -m compileall ..."
python3 -m compileall -q .

echo "[CI-SMOKE] Running pytest installer unit tests..."
pytest tests/installer

detect_config() {
  local path="$1"
  shift
  if [ -f "${path}" ]; then
    local marker
    for marker in "$@"; do
      if grep -q "${marker}" "${path}"; then
        return 0
      fi
    done
  fi
  return 1
}

maybe_run_ruff() {
  if command -v ruff >/dev/null 2>&1; then
    if detect_config "pyproject.toml" "[tool.ruff]" || [ -f "ruff.toml" ] || [ -f ".ruff.toml" ]; then
      echo "[CI-SMOKE] Running ruff check ..."
      ruff check .
    else
      echo "[CI-SMOKE] Ruff config not detected; skipping ruff check."
    fi
  else
    echo "[CI-SMOKE] Ruff executable not found; skipping ruff check."
  fi
}

maybe_run_black() {
  local black_targets=("pyproject.toml" "setup.cfg" "tox.ini")
  if command -v black >/dev/null 2>&1; then
    local has_black_config=1
    for target in "${black_targets[@]}"; do
      if detect_config "${target}" "[tool.black]" "[black]" ; then
        has_black_config=0
        break
      fi
    done
    if [ "${has_black_config}" -eq 0 ]; then
      echo "[CI-SMOKE] Running black --check ..."
      black --check installer tools tests
    else
      echo "[CI-SMOKE] Black config not detected; skipping black --check."
    fi
  else
    echo "[CI-SMOKE] Black executable not found; skipping black --check."
  fi
}

maybe_run_ruff
maybe_run_black
