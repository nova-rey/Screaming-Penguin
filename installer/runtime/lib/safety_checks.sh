#!/bin/sh
# Screaming Penguin safety checks placeholder (Phase 2).
# No real disk safety enforcement yet; logs only.

set -eu

# shellcheck disable=SC1091
. "$(dirname "$0")/logging.sh"

sp_safety_check_placeholder() {
    log_info "Phase 2: safety checks placeholder called."
    log_info "TODO: enforce real disk and configuration safety checks in a later phase."
    # For Phase 2, always succeed.
    return 0
}
