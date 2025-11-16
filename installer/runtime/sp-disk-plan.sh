#!/bin/sh
# Screaming Penguin disk planning skeleton (Phase 2).
# Responsible for planning GPT layout in later phases.
# Currently logs only; no disk operations.

set -eu

# shellcheck disable=SC1091
. "$(dirname "$0")/lib/logging.sh"

sp_disk_plan() {
    log_info "Phase 2: sp_disk_plan called (no-op)."
    log_info "TODO: implement GPT partition planning in a later phase."
    # For Phase 2, return success without doing anything.
    return 0
}
