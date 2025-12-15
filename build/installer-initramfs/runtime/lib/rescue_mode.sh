#!/bin/sh
# shellcheck shell=sh

# Rescue mode helper that logs diagnostics, blocks the write gate, and drops into
# an interactive shell when the installer cannot proceed.

SP_RESCUE_LOG_DEVICE="${SP_LOG_DEVICE:-/dev/console}"
SP_RESCUE_LABEL_DIR="${SP_RESCUE_LABEL_DIR:-/dev/disk/by-label}"
SP_RESCUE_CONSOLE="${SP_RESCUE_CONSOLE:-/dev/console}"

sp_rescue_log_line() {
    if command -v sp_log >/dev/null 2>&1; then
        sp_log "$@"
        return
    fi

    printf '[SP-RESCUE] %s\n' "$*" >>"$SP_RESCUE_LOG_DEVICE" 2>/dev/null || true
}

sp_rescue_write_header() {
    sp_rescue_log_line "state=rescue" "result=enter" "reason=${1:-unknown}"
    sp_rescue_log_line "==== SP RESCUE MODE ===="
    sp_rescue_log_line "Entering rescue mode"
    sp_rescue_log_line "Failure reason: ${1:-unknown}"
    sp_rescue_log_line "Write gate blocked, dropping to shell."
}

sp_rescue_dump_command() {
    label="$1"
    shift

    if ! command -v "$1" >/dev/null 2>&1; then
        sp_rescue_log_line "source=${label}" "note=missing-command" "cmd=$1"
        return
    fi

    if ! output="$("$@" 2>&1)"; then
        status=$?
    else
        status=0
    fi

    if [ -z "$output" ]; then
        sp_rescue_log_line "source=${label}" "note=no-output" "status=${status:-}"
        return
    fi

    printf '%s\n' "$output" | while IFS= read -r line; do
        sp_rescue_log_line "source=${label}" "line=${line:-}"
    done
}

sp_rescue_list_labels() {
    dir="${SP_RESCUE_LABEL_DIR}"
    if [ ! -d "$dir" ]; then
        sp_rescue_log_line "source=by-label" "note=missing" "path=$dir"
        return
    fi

    found=0
    for entry in "$dir"/* "$dir"/.*; do
        [ -e "$entry" ] || continue
        name="$(basename "$entry")"
        [ "$name" = "." ] && continue
        [ "$name" = ".." ] && continue
        found=1
        if command -v readlink >/dev/null 2>&1; then
            target="$(readlink "$entry" 2>/dev/null || true)"
        else
            target=""
        fi
        sp_rescue_log_line "source=by-label" "entry=$name" "target=${target:-unknown}"
    done

    if [ "$found" -eq 0 ]; then
        sp_rescue_log_line "source=by-label" "note=empty" "path=$dir"
    fi
}

sp_rescue_find_shell() {
    if [ -n "${SP_TEST_RESCUE_SHELL:-}" ] && [ -x "${SP_TEST_RESCUE_SHELL:-}" ]; then
        printf '%s\n' "${SP_TEST_RESCUE_SHELL}"
        return 0
    fi

    if [ -n "${SP_RESCUE_SHELL:-}" ] && [ -x "${SP_RESCUE_SHELL}" ]; then
        printf '%s\n' "${SP_RESCUE_SHELL}"
        return 0
    fi

    for candidate in sh bash; do
        if command -v "$candidate" >/dev/null 2>&1; then
            printf '%s\n' "$(command -v "$candidate")"
            return 0
        fi
    done

    for candidate in /bin/sh /bin/bash /usr/bin/sh /usr/bin/bash; do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

sp_rescue_mount_minimal() {
    mount -t proc proc /proc 2>/dev/null || true
    mount -t sysfs sysfs /sys 2>/dev/null || true
    mount -t devtmpfs devtmpfs /dev 2>/dev/null || \
        mount -t tmpfs devtmpfs /dev 2>/dev/null || true
}

sp_rescue_dump_proc_partitions() {
    if [ ! -r /proc/partitions ]; then
        sp_rescue_log_line "source=proc/partitions" "note=missing"
        return
    fi

    sp_rescue_dump_command "proc/partitions" cat /proc/partitions
}

sp_rescue_dump_sys_block() {
    if [ ! -d /sys/block ]; then
        sp_rescue_log_line "source=sysfs" "note=missing" "path=/sys/block"
        return
    fi

    for block in /sys/block/*; do
        if [ ! -d "$block" ]; then
            continue
        fi

        name=$(basename "$block")
        size=$(cat "$block/size" 2>/dev/null || echo "")
        removable=$(cat "$block/removable" 2>/dev/null || echo "")
        sp_rescue_log_line \
            "source=sysfs" \
            "entry=${name}" \
            "size=${size:-unknown}" \
            "removable=${removable:-unknown}"
    done
}

sp_enter_rescue_mode() {
    reason="${1:-missing-config}"

    sp_write_gate_blocked "rescue-reason=${reason}"
    sp_rescue_write_header "$reason"
    sp_rescue_mount_minimal
    sp_rescue_dump_sys_block
    sp_rescue_dump_proc_partitions
    sp_rescue_list_labels

    console_path="${SP_TEST_RESCUE_CONSOLE:-${SP_RESCUE_CONSOLE:-/dev/console}}"
    shell_path="$(sp_rescue_find_shell || true)"

    if [ -n "${shell_path:-}" ]; then
        sp_rescue_log_line "state=rescue" "note=launching-shell" "shell=${shell_path}" "console=${console_path}"
        while :; do
            # Open console read/write once, then reuse the FD (avoids ShellCheck SC2094).
            exec 3<>"$console_path"
            "$shell_path" -i <&3 >&3 2>&3
            exit_status=$?
            sp_rescue_log_line \
                "state=rescue" \
                "note=shell-exited" \
                "shell=${shell_path}" \
                "status=${exit_status:-}"
            sleep 1
        done
    fi

    sp_rescue_log_line "state=rescue" "note=no-shell" "console=${console_path}"
    while :; do
        sleep 3600
    done
}
