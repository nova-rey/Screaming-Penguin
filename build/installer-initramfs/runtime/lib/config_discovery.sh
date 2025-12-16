#!/bin/sh
# shellcheck shell=sh

# Fallback logging helpers for test contexts (init defines these normally).
if ! command -v sp_log >/dev/null 2>&1; then
    sp_log() {
        printf '[SP-INSTALLER] %s\n' "$*" >&2
    }
fi

if ! command -v sp_write_gate_blocked >/dev/null 2>&1; then
    sp_write_gate_blocked() {
        sp_log "state=write-gate" "result=blocked" "$@"
    }
fi

SP_RUNTIME_LIB_DIR="${SP_RUNTIME_LIB_DIR:-$(cd "$(dirname "$0")" && pwd)}"
SP_RESCUE_MODE_LIB="$SP_RUNTIME_LIB_DIR/rescue_mode.sh"
if [ -f "$SP_RESCUE_MODE_LIB" ]; then
    # shellcheck disable=SC1090
    # shellcheck source=installer/runtime/lib/rescue_mode.sh
    . "$SP_RESCUE_MODE_LIB"
fi

SP_CONFIG_LABEL="${SP_CONFIG_LABEL:-${SP_CONFIG_LABEL_NAME:-SP_CONFIG}}"
SP_CONFIG_LABEL_NAME="${SP_CONFIG_LABEL_NAME:-$SP_CONFIG_LABEL}"
SP_CONFIG_MOUNTPOINT="${SP_CONFIG_MOUNTPOINT:-${SP_CONFIG_MOUNT_POINT:-/config}}"
SP_CONFIG_MOUNT_POINT="${SP_CONFIG_MOUNTPOINT}"
SP_CONFIG_FILE="${SP_CONFIG_FILE:-installer-config.yml}"
SP_OS_DIR="${SP_OS_DIR:-os}"
SP_PROC_ROOT="${SP_PROC_ROOT:-/proc}"
SP_SYS_BLOCK_ROOT="${SP_SYS_BLOCK_ROOT:-/sys/block}"
SP_DEV_ROOT="${SP_DEV_ROOT:-/dev}"
SP_CONFIG_DISCOVERY_MAX_ATTEMPTS="${SP_CONFIG_DISCOVERY_MAX_ATTEMPTS:-1}"

SP_CONFIG_DISCOVERY_ATTEMPTS_LOG=""
SP_CONFIG_DISCOVERY_ATTEMPT_COUNT=0
SP_CONFIG_DISCOVERY_TRIED=""

sp_record_config_candidate() {
    candidate="$1"
    reason="$2"
    label="$3"
    SP_CONFIG_DISCOVERY_ATTEMPTS_LOG="${SP_CONFIG_DISCOVERY_ATTEMPTS_LOG}${candidate}|${reason}|${label}
"
    SP_CONFIG_DISCOVERY_ATTEMPT_COUNT=$((SP_CONFIG_DISCOVERY_ATTEMPT_COUNT + 1))
}

sp_log_candidate_summary() {
    if [ "$SP_CONFIG_DISCOVERY_ATTEMPT_COUNT" -eq 0 ]; then
        sp_log "state=discover-config" "phase=candidate-summary" "note=no-candidates"
        return
    fi

    printf '%s' "$SP_CONFIG_DISCOVERY_ATTEMPTS_LOG" | while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        candidate="${entry%%|*}"
        rest="${entry#*|}"
        reason="${rest%%|*}"
        label="${rest#*|}"
        sp_log "state=discover-config" \
            "phase=candidate-summary" \
            "candidate=${candidate:-unknown}" \
            "reason=${reason:-unknown}" \
            "label=${label:-unknown}"
    done
}

sp_cleanup_mount_point() {
    target="${SP_CONFIG_MOUNTPOINT:-}"
    if [ -z "$target" ] || [ "$target" = "/" ]; then
        return
    fi
    if [ -d "$target" ]; then
        rm -rf "${target:?}"/* 2>/dev/null || true
        rm -rf "${target:?}"/.[!.]* 2>/dev/null || true
    fi
}

sp_unmount_config_point() {
    target="${SP_CONFIG_MOUNTPOINT:-}"
    if [ -z "$target" ]; then
        return
    fi
    umount "$target" >/dev/null 2>&1 || true
    sp_cleanup_mount_point
}

sp_realpath() {
    path="$1"
    if [ -z "$path" ]; then
        return 1
    fi

    if command -v readlink >/dev/null 2>&1; then
        resolved=$(readlink -f "$path" 2>/dev/null || true)
        if [ -n "$resolved" ]; then
            printf '%s\n' "$resolved"
            return 0
        fi
    fi

    printf '%s\n' "$path"
    return 0
}

sp_mark_candidate_tried() {
    candidate="$1"
    case ":${SP_CONFIG_DISCOVERY_TRIED}:" in
        *:"$candidate":*)
            ;;
        *)
            SP_CONFIG_DISCOVERY_TRIED="${SP_CONFIG_DISCOVERY_TRIED}:$candidate"
            ;;
    esac
}

sp_candidate_already_tried() {
    candidate="$1"
    case ":${SP_CONFIG_DISCOVERY_TRIED}:" in
        *:"$candidate":*)
            return 0
            ;;
    esac
    return 1
}

sp_mount_candidate() {
    candidate="$1"
    [ -n "$candidate" ] || return 1
    mkdir -p "$SP_CONFIG_MOUNTPOINT" 2>/dev/null || true

    for fs in vfat ext4; do
        mount -o ro -t "$fs" "$candidate" "$SP_CONFIG_MOUNTPOINT" >/dev/null 2>&1 && return 0
    done

    return 1
}

sp_log_candidate_attempt() {
    phase="$1"
    candidate="$2"
    label="$3"

    sp_log "state=discover-config" \
        "phase=${phase}" \
        "result=attempt" \
        "candidate=${candidate:-unknown}" \
        "label=${label:-unknown}"
}

sp_attempt_mount_candidate() {
    candidate="$1"
    phase="$2"
    label="$3"

    resolved="$1"
    resolved=$(sp_realpath "$resolved" || printf '%s\n' "$candidate")
    if [ -z "$resolved" ]; then
        sp_log "state=discover-config" "phase=${phase}" "candidate=${candidate:-unknown}" "result=reject" "reason=empty-path"
        sp_record_config_candidate "${candidate:-unknown}" "empty-path" "${label:-unknown}"
        return 1
    fi

    if sp_candidate_already_tried "$resolved"; then
        sp_log "state=discover-config" \
            "phase=${phase}" \
            "candidate=${resolved}" \
            "result=skip" \
            "reason=duplicate"
        return 1
    fi

    sp_mark_candidate_tried "$resolved"
    sp_log_candidate_attempt "$phase" "$resolved" "$label"

    if [ ! -e "$resolved" ]; then
        sp_log "state=discover-config" \
            "phase=${phase}" \
            "candidate=${resolved}" \
            "result=reject" \
            "reason=device-missing"
        sp_record_config_candidate "$resolved" "device-missing" "${label:-unknown}"
        return 1
    fi

    sp_cleanup_mount_point
    if sp_mount_candidate "$resolved"; then
        mount_point="${SP_CONFIG_MOUNTPOINT%/}"
        config_path="${mount_point}/${SP_CONFIG_FILE}"
        payload_dir="${mount_point}/${SP_OS_DIR}"
        if [ -f "$config_path" ]; then
            if [ -d "$payload_dir" ]; then
                SP_CONFIG_PATH="$config_path"
                export SP_CONFIG_PATH
                CONFIG_MOUNT="${SP_CONFIG_MOUNTPOINT:-/config}"
                export CONFIG_MOUNT
                sp_log "state=discover-config" \
                    "phase=${phase}" \
                    "result=found" \
                    "path=${SP_CONFIG_PATH}" \
                    "candidate=${resolved}" \
                    "label=${label:-}"
                sp_log "config-path=${SP_CONFIG_PATH}"
                sp_log "payload-dir=${payload_dir}"
                sp_log "config-dev=${resolved}"
                return 0
            fi
            reason="missing-payload-dir"
        else
            reason="missing-config-file"
        fi
    else
        reason="mount-failed"
    fi

    sp_log "state=discover-config" \
        "phase=${phase}" \
        "candidate=${resolved}" \
        "result=reject" \
        "reason=${reason}" \
        "label=${label:-}"
    sp_record_config_candidate "$resolved" "$reason" "${label:-unknown}"
    sp_unmount_config_point
    return 1
}

sp_should_skip_candidate() {
    candidate="$1"
    case "$candidate" in
        loop*|ram*|fd*|sr*|mmcblk*boot*|zram*|dm-*|md*)
            return 0
            ;;
    esac
    return 1
}

sp_partition_has_sys_entry() {
    candidate="$1"
    if [ ! -d "$SP_SYS_BLOCK_ROOT" ]; then
        return 1
    fi

    for block_dir in "$SP_SYS_BLOCK_ROOT"/*; do
        if [ ! -d "$block_dir" ]; then
            continue
        fi

        if [ -d "${block_dir%/}/$candidate" ]; then
            return 0
        fi
    done

    return 1
}

sp_partition_candidates() {
    partitions_file="${SP_PROC_ROOT%/}/partitions"
    if [ ! -r "$partitions_file" ]; then
        return 1
    fi

    awk 'NR>2 && length($4)>0 {print $4}' "$partitions_file" | LC_ALL=C sort
}

sp_resolve_blkid() {
    if [ -n "${SP_CONFIG_DISCOVERY_BLKID_BIN:-}" ]; then
        return 0
    fi

    sp_blkid="$(command -v blkid 2>/dev/null || true)"
    if [ -z "$sp_blkid" ]; then
        return 1
    fi

    SP_CONFIG_DISCOVERY_BLKID_BIN="$sp_blkid"
    return 0
}

sp_probe_fs_label() {
    device="$1"
    if [ -z "$device" ]; then
        return 1
    fi

    label="$("$SP_CONFIG_DISCOVERY_BLKID_BIN" -s LABEL -o value "$device" 2>/dev/null || true)"
    label="$(sp_trim "$label")"
    if [ -n "$label" ]; then
        printf '%s\n' "$label"
        return 0
    fi

    output="$("$SP_CONFIG_DISCOVERY_BLKID_BIN" -o export "$device" 2>/dev/null || true)"
    label="$(printf '%s\n' "$output" | awk -F= '/^LABEL=/ {print $2; exit}')"
    label="$(sp_trim "$label")"
    printf '%s\n' "$label"
    return 0
}

sp_search_by_label() {
    partitions_file="${SP_PROC_ROOT%/}/partitions"
    if [ ! -r "$partitions_file" ]; then
        sp_log "state=discover-config" \
            "phase=probe-label" \
            "result=skip" \
            "reason=proc-missing" \
            "path=${partitions_file}"
        return 1
    fi

    if [ ! -d "$SP_SYS_BLOCK_ROOT" ]; then
        sp_log "state=discover-config" \
            "phase=probe-label" \
            "result=skip" \
            "reason=sysfs-missing" \
            "path=${SP_SYS_BLOCK_ROOT}"
        return 1
    fi

    candidates="$(sp_partition_candidates)"
    if [ -z "$candidates" ]; then
        sp_log "state=discover-config" \
            "phase=probe-label" \
            "result=skip" \
            "reason=no-partitions"
        return 1
    fi

    for candidate in $candidates; do
        [ -n "$candidate" ] || continue
        if sp_should_skip_candidate "$candidate"; then
            continue
        fi
        if ! sp_partition_has_sys_entry "$candidate"; then
            continue
        fi

        device="${SP_DEV_ROOT%/}/$candidate"
        label="$(sp_probe_fs_label "$device")"
        label="$(sp_trim "$label")"
        if [ "$label" != "$SP_CONFIG_LABEL" ]; then
            sp_log "state=discover-config" \
                "phase=probe-label" \
                "result=skip" \
                "candidate=${device}" \
                "reason=label-mismatch" \
                "label=${label:-unknown}"
            sp_record_config_candidate "$device" "label-mismatch" "${label:-unknown}"
            continue
        fi

        sp_log_candidate_attempt "probe-label" "$device" "$label"
        if sp_attempt_mount_candidate "$device" "probe-label" "$label"; then
            return 0
        fi
    done

    return 1
}

sp_discover_config() {
    SP_CONFIG_DISCOVERY_ATTEMPTS_LOG=""
    SP_CONFIG_DISCOVERY_ATTEMPT_COUNT=0
    SP_CONFIG_DISCOVERY_TRIED=""

    sp_log "state=discover-config" "phase=start"

    if ! sp_resolve_blkid; then
        printf '[SP-INSTALLER][FATAL] missing-binary cmd=blkid\n' >>"$SP_LOG_DEVICE" 2>&1
        sp_log_candidate_summary
        sp_enter_rescue_mode "missing-blkid"
        return 1
    fi

    sp_log "config-resolver=probe-label" "config-label=${SP_CONFIG_LABEL}"

    attempts="${SP_CONFIG_DISCOVERY_MAX_ATTEMPTS}"
    case "${attempts}" in
        ''|*[!0-9]*)
            attempts=1
            ;;
        *)
            if [ "${attempts}" -lt 1 ]; then
                attempts=1
            fi
            ;;
    esac

    attempt=1
    while [ "$attempt" -le "$attempts" ]; do
        sp_log "state=discover-config" "phase=attempt" "number=${attempt}"

        if sp_search_by_label; then
            return 0
        fi

        attempt=$((attempt + 1))
    done

    printf '[SP-INSTALLER][FATAL] config-label-not-found label=%s candidates=%s\n' \
        "$SP_CONFIG_LABEL" "${SP_CONFIG_DISCOVERY_ATTEMPT_COUNT:-0}" >>"$SP_LOG_DEVICE" 2>&1
    sp_log "state=discover-config" \
        "result=not-found" \
        "attempts=${SP_CONFIG_DISCOVERY_ATTEMPT_COUNT}"
    sp_log_candidate_summary
    sp_enter_rescue_mode "missing-config"
    return 1
}
