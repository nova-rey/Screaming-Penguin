#!/bin/sh
# Phase 2 placeholder: launch-runtime hook.
# Intended to run the Screaming Penguin runtime once initramfs is ready.

set -eu

SP_LOG_DEV="/dev/console"

log() {
    echo "[sp-hook/launch-runtime] $*" >"$SP_LOG_DEV"
}

log "Entered launch-runtime hook (Phase 2)."
log "TODO: In later phases, this will exec the sp-installer runtime."

# For Phase 2, we only log. No runtime is actually executed here yet.
