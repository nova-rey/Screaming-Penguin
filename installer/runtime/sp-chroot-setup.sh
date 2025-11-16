#!/bin/sh
# Screaming Penguin chroot setup skeleton (Phase 2).
# Will perform hostname, locale, user, SSH, and GRUB configuration later.
# Currently logs only; no chroot or configuration is performed.

set -eu

# shellcheck disable=SC1091
. "$(dirname "$0")/lib/logging.sh"

sp_chroot_setup() {
    log_info "Phase 2: sp_chroot_setup called (no-op)."
    log_info "TODO: implement chroot configuration and GRUB setup in a later phase."
    return 0
}
