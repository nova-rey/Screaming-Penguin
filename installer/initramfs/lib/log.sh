#!/bin/sh
# Screaming Penguin initramfs logging helpers

SP_LOG_DIR="/run/sp/log"
SP_LOG_FILE="${SP_LOG_DIR}/init.log"

sp_log_init() {
    # Ensure log directory exists; best-effort only.
    mkdir -p "${SP_LOG_DIR}" 2>/dev/null || true
}

# Generic logger: $1=level, $2=tag, $3..=message
_sp_log() {
    level="$1"
    tag="$2"
    shift 2
    msg="$*"

    # Basic timestamp if available; otherwise just use "-"
    if command -v date >/dev/null 2>&1; then
        ts="$(date +'%Y-%m-%dT%H:%M:%S%z')"
    else
        ts="-"
    fi

    line="${ts} ${level} ${tag} ${msg}"

    # Always print to console
    echo "${line}" >&2

    # Best-effort write to log file (may be in tmpfs early on)
    if [ -n "${SP_LOG_FILE}" ]; then
        # shellcheck disable=SC2129
        echo "${line}" >>"${SP_LOG_FILE}" 2>/dev/null || true
    fi
}

sp_log_info() {
    # $1=tag, rest=message
    tag="$1"
    shift
    _sp_log "INFO" "${tag}" "$*"
}

sp_log_warn() {
    tag="$1"
    shift
    _sp_log "WARN" "${tag}" "$*"
}

sp_log_error() {
    tag="$1"
    shift
    _sp_log "ERROR" "${tag}" "$*"
}

# Fatal error helper: log and drop to shell or exit
sp_die() {
    tag="$1"
    shift
    _sp_log "ERROR" "${tag}" "$*"

    # If a recovery shell is available, drop into it.
    if command -v sh >/dev/null 2>&1; then
        echo "Dropping to recovery shell. Type 'exit' to reboot or poweroff." >&2
        sh
    fi

    # Fallback: hard exit
    exit 1
}
