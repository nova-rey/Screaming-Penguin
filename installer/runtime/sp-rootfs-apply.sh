#!/bin/sh
# Screaming Penguin rootfs apply skeleton (Phase 2).
# Will extract the rootfs tarball and set up the root filesystem later.
# Currently logs only; no extraction is performed.

set -eu

# shellcheck disable=SC1091
. "$(dirname "$0")/lib/logging.sh"

sp_rootfs_apply() {
    log_info "Phase 2: sp_rootfs_apply called (no-op)."
    log_info "TODO: implement rootfs extraction and base configuration in a later phase."
    return 0
}
