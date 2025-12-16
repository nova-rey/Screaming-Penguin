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
SP_CONFIG_MOUNTPOINT="${SP_CONFIG_MOUNTPOINT:-/config}"
SP_CONFIG_MOUNT_POINT="${SP_CONFIG_MOUNT_POINT:-$SP_CONFIG_MOUNTPOINT}"
SP_CONFIG_FILE="${SP_CONFIG_FILE:-installer-config.yml}"
SP_OS_DIR="${SP_OS_DIR:-os}"
SP_SYS_BLOCK_ROOT="${SP_SYS_BLOCK_ROOT:-/sys/block}"
SP_DEV_ROOT="${SP_DEV_ROOT:-/dev}"
SP_PROC_ROOT="${SP_PROC_ROOT:-/proc}"
SP_CONFIG_DISCOVERY_EXCLUDE_PREFIXES="${SP_CONFIG_DISCOVERY_EXCLUDE_PREFIXES:-loop ram fd sr dm}"

SP_CONFIG_DISCOVERY_ATTEMPTS_LOG=""
SP_CONFIG_DISCOVERY_ATTEMPT_COUNT=0
SP_CONFIG_DISCOVERY_TRIED=""
SP_CONFIG_CANDIDATE_LIST=""
SP_CONFIG_CANDIDATE_COUNT=0
SP_CONFIG_BASE_DEVICES=":"

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
    target="${SP_CONFIG_MOUNT_POINT:-}"
    if [ -z "$target" ] || [ "$target" = "/" ]; then
        return
    fi
    if [ -d "$target" ]; then
        rm -rf "${target:?}"/* 2>/dev/null || true
        rm -rf "${target:?}"/.[!.]* 2>/dev/null || true
    fi
}

sp_unmount_config_point() {
    target="${SP_CONFIG_MOUNT_POINT:-}"
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
    mkdir -p "$SP_CONFIG_MOUNT_POINT" 2>/dev/null || true

    for fs in vfat ext4; do
        mount -o ro -t "$fs" "$candidate" "$SP_CONFIG_MOUNT_POINT" >/dev/null 2>&1 && return 0
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
        config_path="$SP_CONFIG_MOUNT_POINT/$SP_CONFIG_FILE"
        payload_dir="${SP_CONFIG_MOUNT_POINT%/}/${SP_OS_DIR}"
        if [ -f "$config_path" ] && [ -d "$payload_dir" ]; then
            SP_CONFIG_PATH="$config_path"
            export SP_CONFIG_PATH
            CONFIG_MOUNT="${SP_CONFIG_MOUNT_POINT:-/config}"
            export CONFIG_MOUNT
            sp_log "state=discover-config" \
                "phase=${phase}" \
                "result=found" \
                "path=${SP_CONFIG_PATH}" \
                "candidate=${resolved}" \
                "label=${label:-}"
            sp_log "config-resolver=probe-label" \
                "config-label=${SP_CONFIG_LABEL}" \
                "config-dev=${resolved}"
            sp_log "config-path=${SP_CONFIG_PATH}"
            sp_log "payload-dir=${payload_dir}"
            return 0
        fi
        if [ ! -f "$config_path" ]; then
            reason="missing-config-file"
        else
            reason="missing-os-dir"
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

sp_log_fatal_marker() {
    message="$1"
    if [ -n "${SP_LOG_DEVICE:-}" ]; then
        printf '[SP-INSTALLER][FATAL] %s\n' "$message" >>"$SP_LOG_DEVICE" 2>/dev/null || true
    fi
    printf '[SP-INSTALLER][FATAL] %s\n' "$message" >&2
}

sp_cache_base_devices() {
    SP_CONFIG_BASE_DEVICES=":"
    if [ ! -d "$SP_SYS_BLOCK_ROOT" ]; then
        return
    fi

    for block_dir in "$SP_SYS_BLOCK_ROOT"/*; do
        if [ ! -d "$block_dir" ]; then
            continue
        fi
        base=$(basename "$block_dir")
        SP_CONFIG_BASE_DEVICES="${SP_CONFIG_BASE_DEVICES}${base}:"
    done
}

sp_is_base_device() {
    candidate="$1"
    case "${SP_CONFIG_BASE_DEVICES}" in
        *:"$candidate":*)
            return 0
            ;;
    esac
    return 1
}

sp_should_skip_candidate() {
    candidate="$1"
    case "$candidate" in
        loop*|ram*|fd*|sr*|dm-*|md*|zram*|mmcblk*boot*)
            return 0
            ;;
    esac

    for prefix in $SP_CONFIG_DISCOVERY_EXCLUDE_PREFIXES; do
        case "$candidate" in
            ${prefix}*)
                return 0
                ;;
        esac
    done

    if sp_is_base_device "$candidate"; then
        return 0
    fi

    return 1
}

sp_collect_partition_candidates() {
    partitions_path="${SP_PROC_ROOT%/}/partitions"
    SP_CONFIG_CANDIDATE_LIST=""
    SP_CONFIG_CANDIDATE_COUNT=0

    if [ ! -r "$partitions_path" ]; then
        sp_log "state=discover-config" \
            "phase=enumerate" \
            "result=skip" \
            "reason=missing-proc" \
            "path=${partitions_path}"
        return 1
    fi

    sp_cache_base_devices

    candidate_buffer=""
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        name="${line##* }"
        [ -n "$name" ] || continue
        if [ "$name" = "name" ]; then
            continue
        fi
        if sp_should_skip_candidate "$name"; then
            continue
        fi
        candidate_buffer="${candidate_buffer}${name}
"
        SP_CONFIG_CANDIDATE_COUNT=$((SP_CONFIG_CANDIDATE_COUNT + 1))
    done < "$partitions_path"

    if [ "$SP_CONFIG_CANDIDATE_COUNT" -eq 0 ]; then
        return 1
    fi

    SP_CONFIG_CANDIDATE_LIST="$(printf '%s' "$candidate_buffer" | sort)"
    return 0
}

sp_trim_label() {
    label="$1"
    label=${label#\"}
    label=${label%\"}
    label=${label#\'}
    label=${label%\'}
    printf '%s' "$label"
}

sp_probe_fs_label() {
    candidate="$1"
    if [ -z "$candidate" ]; then
        return 1
    fi

    if ! output="$(blkid -o export "$candidate" 2>/dev/null)"; then
        return 0
    fi

    label=""
    if [ -n "$output" ]; then
        while IFS= read -r line; do
            case "$line" in
                LABEL=*)
                    label="${line#LABEL=}"
                    break
                    ;;
            esac
        done <<EOF
$output
EOF
    fi

    label="$(sp_trim_label "$label")"
    if [ -n "$label" ]; then
        printf '%s\n' "$label"
    fi
    return 0
}

sp_log_label_not_found() {
    sp_log_fatal_marker "config-label-not-found label=${SP_CONFIG_LABEL} candidates=${SP_CONFIG_CANDIDATE_COUNT:-0}"
    sp_log "state=discover-config" \
        "phase=probe-label" \
        "result=not-found" \
        "config-label=${SP_CONFIG_LABEL}" \
        "candidates=${SP_CONFIG_CANDIDATE_COUNT:-0}"
}

sp_discover_config() {
    SP_CONFIG_DISCOVERY_ATTEMPTS_LOG=""
    SP_CONFIG_DISCOVERY_ATTEMPT_COUNT=0
    SP_CONFIG_DISCOVERY_TRIED=""

    sp_log "state=discover-config" "phase=start"

    if ! command -v blkid >/dev/null 2>&1; then
        sp_log "state=discover-config" "phase=probe-label" "result=error" "reason=missing-binary" "binary=blkid"
        sp_log_fatal_marker "missing-dependency binary=blkid"
        sp_enter_rescue_mode "missing-dependency"
        return 1
    fi

    if ! sp_collect_partition_candidates; then
        sp_log_label_not_found
        sp_log_candidate_summary
        sp_enter_rescue_mode "missing-config"
        return 1
    fi

    sp_log "state=discover-config" "phase=probe-label" "result=start" "resolver=probe-label" "candidates=${SP_CONFIG_CANDIDATE_COUNT}"

    for device in $SP_CONFIG_CANDIDATE_LIST; do
        candidate="${SP_DEV_ROOT%/}/$device"
        label="$(sp_probe_fs_label "$candidate" || true)"
        if [ "$label" = "$SP_CONFIG_LABEL" ]; then
            sp_log "state=discover-config" \
                "phase=probe-label" \
                "candidate=${candidate}" \
                "result=match" \
                "label=${label}"
            if sp_attempt_mount_candidate "$candidate" "probe-label" "$label"; then
                return 0
            fi
            continue
        fi

        if [ -n "$label" ]; then
            reason="label-mismatch"
        else
            reason="no-label"
        fi
        sp_log "state=discover-config" \
            "phase=probe-label" \
            "candidate=${candidate}" \
            "result=skip" \
            "reason=${reason}" \
            "label=${label:-unknown}"
        sp_record_config_candidate "$candidate" "$reason" "${label:-unknown}"
    done

    sp_log_label_not_found
    sp_log_candidate_summary
    sp_enter_rescue_mode "missing-config"
    return 1
}
