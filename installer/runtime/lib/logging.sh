#!/bin/sh
# Screaming Penguin logging library (Phase 2 skeleton).
# Provides simple log functions for runtime scripts.
# Non-destructive, safe to source from any context.

set -u

: "${SP_LOG_FILE:=/tmp/screaming-penguin.log}"

_sp_log() {
    level="$1"
    shift
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "no-time")"
    msg="[$timestamp] [$level] $*"
    echo "$msg"
    # Best-effort file logging; ignore failures.
    {
        echo "$msg" >>"$SP_LOG_FILE"
    } 2>/dev/null || :
}

log_info() {
    _sp_log "INFO" "$@"
}

log_warn() {
    _sp_log "WARN" "$@"
}

log_error() {
    _sp_log "ERROR" "$@"
}
