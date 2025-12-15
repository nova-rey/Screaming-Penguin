#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

announce() {
  echo "[CI-ISO] $1"
}

announce "Stage: runtime build starting..."
bash tools/build_runtime.sh
announce "Stage: runtime build completed."

announce "Stage: installer initramfs build starting..."
bash tools/build_installer_initramfs.sh
announce "Stage: installer initramfs build completed."

announce "Stage: ISO assembly starting..."
SP_SKIP_INSTALLER_INITRAMFS_BUILD=1 bash tools/make_installer_iso.sh
announce "Stage: ISO assembly completed."
