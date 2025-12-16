#!/bin/sh
# Screaming Penguin logging library (Phase 5).
# Provides simple logging to console and an optional log file.
#
# Safe to source from any context (initramfs or runtime).

set -u

: "${SP_LOG_FILE:=/tmp/screaming-penguin.log}"

_sp_log() {
    level="$1"
    shift
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "no-time")"
    msg="[$timestamp] [$level] $*"

    # Console log
    echo "$msg"

    # Best-effort file logging; ignore failures.
    (
        umask 077
        log_dir="$(dirname "$SP_LOG_FILE")"
        if [ -n "$log_dir" ] && [ "$log_dir" != "." ]; then
            mkdir -p "$log_dir"
        fi
        printf "%s\n" "$msg" >>"$SP_LOG_FILE"
    ) 2>/dev/null || :
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

log_block_devices_snapshot() {
    block_devices=""

    for pattern in /dev/sd* /dev/nvme* /dev/mmcblk*; do
        for dev in $pattern; do
            [ -e "$dev" ] || continue
            block_devices="${block_devices:+$block_devices }$dev"
        done
    done

    mmc_sys=""
    for sys_entry in /sys/block/mmcblk*; do
        [ -e "$sys_entry" ] || continue
        mmc_sys="${mmc_sys:+$mmc_sys }$sys_entry"
    done

    mmc_dev=""
    for dev_entry in /dev/mmcblk*; do
        [ -e "$dev_entry" ] || continue
        mmc_dev="${mmc_dev:+$mmc_dev }$dev_entry"
    done

    block_devices="${block_devices:-none}"
    mmc_sys="${mmc_sys:-none}"
    mmc_dev="${mmc_dev:-none}"

    log_info "[SP-INSTALLER] block-devices=${block_devices} mmc-sys=${mmc_sys} mmc-dev=${mmc_dev}"

    if [ -n "${SP_LOG_DEVICE:-}" ]; then
        printf '[SP-INSTALLER] block-devices=%s mmc-sys=%s mmc-dev=%s\n' "$block_devices" "$mmc_sys" "$mmc_dev" >>"$SP_LOG_DEVICE" 2>/dev/null || true
    fi
}

sp_log_cmd_one_line() {
    label="$1"
    shift

    if [ "$#" -eq 0 ]; then
        log_warn "[SP-INSTALLER] ${label}=<no-cmd>"
        return 0
    fi

    rc=0
    if ! output="$("$@" 2>&1)"; then
        rc=$?
    fi

    output="$(printf '%s' "$output" | tr '\n' ' ')"
    output="${output:-none}"

    if [ "$rc" -eq 0 ]; then
        log_info "[SP-INSTALLER] ${label}=${output}"
    else
        log_warn "[SP-INSTALLER] ${label}=${output}"
    fi

    return 0
}

sp_log_kernel_and_modules_snapshot() {
    sp_log_cmd_one_line "kernel_release" uname -r

    # shellcheck disable=SC2016
    sp_log_cmd_one_line "lib_modules_dirs" sh -c '
        dirs="$(ls -1 /lib/modules 2>/dev/null | tr "\n" " " || true)"
        if [ -n "$dirs" ]; then
            printf "%s" "$dirs"
        else
            printf "missing"
        fi
    '

    kernel_release="$(uname -r 2>/dev/null || true)"
    modules_dir="/lib/modules"
    if [ -n "$kernel_release" ]; then
        modules_dir="${modules_dir}/${kernel_release}"
    fi

    # shellcheck disable=SC2016
    sp_log_cmd_one_line "kernel_modules_dir_exists" sh -c '
        if [ -d "$1" ]; then
            printf "1"
        else
            printf "0"
        fi
    ' -- "$modules_dir"
}

sp_log_sys_block_snapshot() {
    tag="$1"
    if [ -z "$tag" ]; then
        return 0
    fi

    # shellcheck disable=SC2016
    sp_log_cmd_one_line "sys_block_${tag}" sh -c '
        entries="$(ls -1 /sys/block 2>/dev/null | tr "\n" " " || true)"
        if [ -n "$entries" ]; then
            printf "%s" "$entries"
        else
            printf "none"
        fi
    '
}
