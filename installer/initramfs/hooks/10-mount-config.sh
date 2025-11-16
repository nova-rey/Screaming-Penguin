#!/bin/sh
# Phase 2 placeholder: mount-config hook.
# No real mount logic yet; logs only.

set -eu

SP_LOG_DEV="/dev/console"

log() {
    echo "[sp-hook/mount-config] $*" >"$SP_LOG_DEV"
}

log "Entered mount-config hook (Phase 2)."
log "TODO: Implement real /config discovery and mounting in a later phase."
