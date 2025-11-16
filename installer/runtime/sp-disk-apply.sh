#!/bin/sh
# Screaming Penguin disk apply skeleton (Phase 2).
# Will apply partitioning and filesystem changes in later phases.
# Currently logs only; strictly non-destructive.

set -eu

# shellcheck disable=SC1091
. "$(dirname "$0")/lib/logging.sh"

sp_disk_apply() {
    log_info "Phase 2: sp_disk_apply called (no-op)."
    log_info "TODO: implement disk partitioning and filesystem creation in a later phase."
    # For Phase 2, do nothing and succeed.
    return 0
}
