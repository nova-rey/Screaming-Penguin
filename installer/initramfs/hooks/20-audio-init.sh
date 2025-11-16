#!/bin/sh
# Phase 2 placeholder: audio-init hook.
# No real audio initialization yet; logs only.

set -eu

SP_LOG_DEV="/dev/console"

log() {
    echo "[sp-hook/audio-init] $*" >"$SP_LOG_DEV"
}

log "Entered audio-init hook (Phase 2)."
log "TODO: Implement optional beep or espeak-ng initialization in a later phase."
