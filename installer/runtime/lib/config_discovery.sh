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

SP_STORAGE_BOOTSTRAP_LIB="$SP_RUNTIME_LIB_DIR/storage_bootstrap.sh"
if [ -f "$SP_STORAGE_BOOTSTRAP_LIB" ]; then
    # shellcheck disable=SC1090
    # shellcheck source=installer/runtime/lib/storage_bootstrap.sh
    . "$SP_STORAGE_BOOTSTRAP_LIB"
fi

SP_CONFIG_LABEL_NAME_ENV="${SP_CONFIG_LABEL_NAME:-}"
SP_CONFIG_LABEL_NAME="${SP_CONFIG_LABEL_NAME_ENV:-${SP_CONFIG_LABEL:-SP_CONFIG}}"
SP_CONFIG_LABEL_REQUESTED=0
if [ -n "${SP_CONFIG_LABEL_NAME_ENV}" ] || [ -n "${SP_CONFIG_LABEL:-}" ]; then
    SP_CONFIG_LABEL_REQUESTED=1
fi
SP_CONFIG_MOUNT_POINT="${SP_CONFIG_MOUNT_POINT:-/config}"
SP_CONFIG_FILE="${SP_CONFIG_FILE:-installer-config.yml}"
SP_SYS_BLOCK_ROOT="${SP_SYS_BLOCK_ROOT:-/sys/block}"
SP_DEV_ROOT="${SP_DEV_ROOT:-/dev}"
SP_PROC_PARTITIONS="${SP_PROC_PARTITIONS:-/proc/partitions}"
SP_CONFIG_DISCOVERY_MAX_ATTEMPTS="${SP_CONFIG_DISCOVERY_MAX_ATTEMPTS:-1}"
SP_CONFIG_DISCOVERY_EXCLUDE_PREFIXES="${SP_CONFIG_DISCOVERY_EXCLUDE_PREFIXES:-loop ram fd sr dm}"
SP_CONFIG_LABEL_PROBE_CANDIDATES=0
SP_CONFIG_LABEL_DEVICE=""

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

sp_log_fatal_marker() {
    message="$1"
    log_device="${SP_LOG_DEVICE:-}"
    if [ -n "$log_device" ]; then
        printf '[SP-INSTALLER][FATAL] %s\n' "$message" >>"$log_device" 2>&1 || true
    else
        printf '[SP-INSTALLER][FATAL] %s\n' "$message" >&2 || true
    fi
}

sp_find_partition_by_fs_label() {
    label="$1"
    partitions="${SP_PROC_PARTITIONS:-/proc/partitions}"
    SP_CONFIG_LABEL_PROBE_CANDIDATES=0

    if [ -z "$label" ]; then
        return 1
    fi

    if ! command -v blkid >/dev/null 2>&1; then
        sp_log_fatal_marker "blkid-not-found"
        return 1
    fi

    if [ ! -r "$partitions" ]; then
        return 1
    fi

    candidate_count=0
    while IFS= read -r line; do
        set -- $line
        major="$1"
        name="$4"

        if [ -z "$major" ]; then
            continue
        fi

        case "$major" in
            ''|*[!0-9]*)
                continue
                ;;
        esac

        if [ -z "$name" ]; then
            continue
        fi

        candidate="${SP_DEV_ROOT%/}/${name}"
        if [ ! -e "$candidate" ]; then
            continue
        fi

        candidate_count=$((candidate_count + 1))
        blkid_output="$(blkid -o export "$candidate" 2>/dev/null || true)"
        label_value=""
        while IFS= read -r line; do
            case "$line" in
                LABEL=*)
                    label_value="${line#LABEL=}"
                    break
                    ;;
            esac
        done <<__BLKID_EXPORT__
$blkid_output
__BLKID_EXPORT__

        if [ "$label_value" = "$label" ]; then
            SP_CONFIG_LABEL_PROBE_CANDIDATES="$candidate_count"
            SP_CONFIG_LABEL_DEVICE="$candidate"
            return 0
        fi
    done < "$partitions"

    SP_CONFIG_LABEL_PROBE_CANDIDATES="$candidate_count"
    return 1
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
        if [ -f "$config_path" ]; then
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
            return 0
        fi
        reason="missing-config-file"
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

sp_try_label_candidate() {
    sp_log "config-resolver=probe-label"
    sp_log "config-label=${SP_CONFIG_LABEL_NAME}"

    if sp_find_partition_by_fs_label "$SP_CONFIG_LABEL_NAME"; then
        target="${SP_CONFIG_LABEL_DEVICE:-}"
        sp_log "config-dev=${target}"
        if sp_attempt_mount_candidate "$target" "label" "$SP_CONFIG_LABEL_NAME"; then
            return 0
        fi
        return 1
    fi

    return 1
}

sp_should_skip_device() {
    base="$1"
    prefixes="${SP_CONFIG_DISCOVERY_EXCLUDE_PREFIXES:-}"

    for prefix in $prefixes; do
        case "$base" in
            "$prefix"*)
                return 0
                ;;
        esac
    done

    return 1
}

sp_try_removable_candidates() {
    if [ ! -d "$SP_SYS_BLOCK_ROOT" ]; then
        sp_log "state=discover-config" "phase=removable" "result=skip" "reason=sysfs-missing" "path=${SP_SYS_BLOCK_ROOT}"
        return 1
    fi

    found=0
    for block_dir in "$SP_SYS_BLOCK_ROOT"/*; do
        if [ ! -d "$block_dir" ]; then
            continue
        fi

        base=$(basename "$block_dir")
        if sp_should_skip_device "$base"; then
            continue
        fi

        removable_file="$block_dir/removable"
        removable="$(cat "$removable_file" 2>/dev/null || echo "0")"
        if [ "$removable" != "1" ]; then
            continue
        fi

        candidate="${SP_DEV_ROOT%/}/$base"
        sp_log "state=discover-config" "phase=removable" "result=discovered" "candidate=${candidate}"
        found=1
        if sp_attempt_mount_candidate "$candidate" "removable" "$base"; then
            return 0
        fi
    done

    if [ "$found" -eq 0 ]; then
        sp_log "state=discover-config" "phase=removable" "result=skip" "reason=no-removable"
    fi

    return 1
}

sp_try_partition_heuristics() {
    if [ ! -d "$SP_SYS_BLOCK_ROOT" ]; then
        return 1
    fi

    for block_dir in "$SP_SYS_BLOCK_ROOT"/*; do
        if [ ! -d "$block_dir" ]; then
            continue
        fi

        base=$(basename "$block_dir")
        if sp_should_skip_device "$base"; then
            continue
        fi

        case "$base" in
            nvme*|mmcblk*)
                prefix="${base}p"
                ;;
            *)
                prefix="${base}"
                ;;
        esac

        part_index=1
        while [ "$part_index" -le 4 ]; do
            part_name="${prefix}${part_index}"
            candidate="${SP_DEV_ROOT%/}/${part_name}"
            sp_log "state=discover-config" "phase=partition-heuristic" "result=discovered" "candidate=${candidate}"
            if sp_attempt_mount_candidate "$candidate" "partition-heuristic" "$part_name"; then
                return 0
            fi
            part_index=$((part_index + 1))
        done
    done

    return 1
}

sp_try_partition_candidates() {
    if [ ! -d "$SP_SYS_BLOCK_ROOT" ]; then
        sp_log "state=discover-config" "phase=partition" "result=skip" "reason=sysfs-missing" "path=${SP_SYS_BLOCK_ROOT}"
        return 1
    fi

    found=0
    for block_dir in "$SP_SYS_BLOCK_ROOT"/*; do
        if [ ! -d "$block_dir" ]; then
            continue
        fi

        base=$(basename "$block_dir")
        if sp_should_skip_device "$base"; then
            continue
        fi

        for part_dir in "$block_dir"/"$base"*; do
            if [ ! -e "$part_dir" ]; then
                continue
            fi

            part_base=$(basename "$part_dir")
            if [ "$part_base" = "$base" ]; then
                continue
            fi

            candidate="${SP_DEV_ROOT%/}/$part_base"
            sp_log "state=discover-config" "phase=partition" "result=discovered" "candidate=${candidate}"
            found=1
            if sp_attempt_mount_candidate "$candidate" "partition" "$part_base"; then
                return 0
            fi
            if [ -d "$candidate" ] && [ -f "$candidate/$SP_CONFIG_FILE" ]; then
                SP_CONFIG_PATH="$candidate/$SP_CONFIG_FILE"
                export SP_CONFIG_PATH
                CONFIG_MOUNT="${SP_CONFIG_MOUNT_POINT:-/config}"
                export CONFIG_MOUNT
                sp_log "state=discover-config" \
                    "phase=partition" \
                    "result=use-directory" \
                    "candidate=${candidate}" \
                    "path=${SP_CONFIG_PATH}"
                return 0
            fi
        done
    done

    if [ "$found" -eq 0 ]; then
        sp_log "state=discover-config" "phase=partition" "result=skip" "reason=no-partitions"
        if sp_try_partition_heuristics; then
            return 0
        fi
    fi

    return 1
}

sp_discover_config() {
    SP_CONFIG_DISCOVERY_ATTEMPTS_LOG=""
    SP_CONFIG_DISCOVERY_ATTEMPT_COUNT=0
    SP_CONFIG_DISCOVERY_TRIED=""

    if command -v sp_bootstrap_usb_storage >/dev/null 2>&1; then
        sp_bootstrap_usb_storage
    fi

    sp_log "state=discover-config" "phase=start"

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

        if sp_try_label_candidate; then
            return 0
        fi

        if [ "${SP_CONFIG_LABEL_REQUESTED:-0}" -eq 1 ] && [ -z "${SP_CONFIG_LABEL_DEVICE:-}" ]; then
            sp_log_fatal_marker "config-label-not-found label=${SP_CONFIG_LABEL_NAME} candidates=${SP_CONFIG_LABEL_PROBE_CANDIDATES:-0}"
            return 1
        fi

        if sp_try_removable_candidates; then
            return 0
        fi

        if sp_try_partition_candidates; then
            return 0
        fi

        attempt=$((attempt + 1))
    done

    sp_log "state=discover-config" \
        "result=not-found" \
        "attempts=${SP_CONFIG_DISCOVERY_ATTEMPT_COUNT}"
    sp_log_candidate_summary
    sp_enter_rescue_mode "missing-config"
    return 1
}
