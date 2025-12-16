#!/bin/sh
# shellcheck shell=sh

SP_LOG_DEVICE="${SP_LOG_DEVICE:-/dev/stderr}"

# Fallback logging helpers for test contexts (init defines these normally).
if ! command -v sp_log >/dev/null 2>&1; then
    sp_log() {
        printf '[SP-INSTALLER] %s\n' "$*" >>"$SP_LOG_DEVICE" 2>&1
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
SP_CONFIG_LABEL_NAME="${SP_CONFIG_LABEL}"
SP_CONFIG_LABEL_DIR="${SP_CONFIG_LABEL_DIR:-/dev/disk/by-label}"

default_config_mount="${SP_CONFIG_MOUNTPOINT:-${SP_CONFIG_MOUNT_POINT:-/config}}"
SP_CONFIG_MOUNT_POINT="${SP_CONFIG_MOUNT_POINT:-$default_config_mount}"
SP_CONFIG_MOUNTPOINT="$SP_CONFIG_MOUNT_POINT"

SP_CONFIG_FILE="${SP_CONFIG_FILE:-installer-config.yml}"
SP_OS_DIR="${SP_OS_DIR:-os}"
SP_CONFIG_SCAN_REMOVABLE_FALLBACK="${SP_CONFIG_SCAN_REMOVABLE_FALLBACK:-1}"
SP_CONFIG_ALLOW_NONREMOVABLE="${SP_CONFIG_ALLOW_NONREMOVABLE:-0}"

SP_SYS_BLOCK_ROOT="${SP_SYS_BLOCK_ROOT:-/sys/block}"
SP_DEV_ROOT="${SP_DEV_ROOT:-/dev}"
SP_CONFIG_DISCOVERY_MAX_ATTEMPTS="${SP_CONFIG_DISCOVERY_MAX_ATTEMPTS:-1}"
SP_CONFIG_DISCOVERY_EXCLUDE_PREFIXES="${SP_CONFIG_DISCOVERY_EXCLUDE_PREFIXES:-loop ram fd sr dm}"

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

sp_log_fatal() {
    printf '[SP-INSTALLER][FATAL] %s\n' "$*" >>"$SP_LOG_DEVICE" 2>&1 || true
}

sp_parent_block_device_for_partition() {
    part="$1"
    if [ -z "$part" ]; then
        return 1
    fi

    base=$(basename "$part")
    if [ -z "$base" ]; then
        return 1
    fi

    case "$base" in
        nvme*|mmcblk*)
            parent=$(printf '%s\n' "$base" | sed 's/p[0-9]*$//' 2>/dev/null || true)
            ;;
        *)
            parent=$(printf '%s\n' "$base" | sed 's/[0-9]*$//' 2>/dev/null || true)
            ;;
    esac

    if [ -z "$parent" ]; then
        parent="$base"
    fi

    printf '%s\n' "$parent"
    return 0
}

sp_parent_removable_value() {
    parent="$1"
    removable_file="${SP_SYS_BLOCK_ROOT%/}/${parent}/removable"
    if [ ! -e "$removable_file" ]; then
        printf '0'
        return 0
    fi
    cat "$removable_file" 2>/dev/null || printf '0'
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
    parent="$(sp_parent_block_device_for_partition "$resolved" || true)"
    removable="$(sp_parent_removable_value "$parent" || echo "0")"
    if [ "$removable" != "1" ] && [ "${SP_CONFIG_ALLOW_NONREMOVABLE:-0}" != "1" ]; then
        sp_log_fatal "config-media-not-removable dev=${resolved} parent=${parent:-unknown} removable=${removable:-0}"
        sp_enter_rescue_mode "config-media-not-removable"
        return 1
    fi

    if ! sp_mount_candidate "$resolved"; then
        reason="mount-failed"
        sp_log "state=discover-config" \
            "phase=${phase}" \
            "candidate=${resolved}" \
            "result=reject" \
            "reason=${reason}" \
            "label=${label:-}"
        sp_record_config_candidate "$resolved" "$reason" "${label:-unknown}"
        sp_unmount_config_point
        return 1
    fi

    config_path="${SP_CONFIG_MOUNT_POINT%/}/$SP_CONFIG_FILE"
    if [ ! -f "$config_path" ]; then
        sp_log_fatal "config-missing installer-config.yml at ${config_path}"
        sp_unmount_config_point
        sp_enter_rescue_mode "missing-config"
        return 1
    fi

    os_dir="${SP_CONFIG_MOUNT_POINT%/}/${SP_OS_DIR}"
    if [ ! -d "$os_dir" ]; then
        sp_log_fatal "payload-missing os/ at ${os_dir}"
        sp_unmount_config_point
        sp_enter_rescue_mode "missing-payload"
        return 1
    fi

    found=0
    selected_tarball=""
    for entry in "${os_dir}/rootfs.tar"*; do
        if [ ! -f "$entry" ]; then
            continue
        fi
        found=$((found + 1))
        selected_tarball="$entry"
    done

    if [ "$found" -ne 1 ]; then
        sp_log_fatal "payload-ambiguous found=${found} in ${os_dir}"
        sp_unmount_config_point
        sp_enter_rescue_mode "payload-ambiguous"
        return 1
    fi

    SP_ROOTFS_DEFAULT_TARBALL="${selected_tarball}"
    export SP_ROOTFS_DEFAULT_TARBALL

    SP_CONFIG_PATH="$config_path"
    export SP_CONFIG_PATH
    CONFIG_MOUNT="${SP_CONFIG_MOUNT_POINT:-/config}"
    export CONFIG_MOUNT

    if [ "$phase" = "label" ]; then
        source_desc="label:${label:-unknown}"
    else
        source_desc="${phase}:${label:-unknown}"
    fi

    sp_log "config-source=${source_desc}" \
        "dev=${resolved}" \
        "parent=${parent:-unknown}" \
        "removable=${removable:-0}" \
        "mount=${SP_CONFIG_MOUNT_POINT}"
    sp_log "config-path=${SP_CONFIG_PATH}"
    sp_log "payload-dir=${os_dir}"

    sp_log "state=discover-config" \
        "phase=${phase}" \
        "result=found" \
        "path=${SP_CONFIG_PATH}" \
        "candidate=${resolved}" \
        "label=${label:-}"
    return 0
}

sp_try_label_candidate() {
    label_path="${SP_CONFIG_LABEL_DIR%/}/${SP_CONFIG_LABEL_NAME}"
    if [ ! -e "$label_path" ]; then
        sp_log "state=discover-config" \
            "phase=label" \
            "result=skip" \
            "reason=missing-label" \
            "path=${label_path}"
        return 1
    fi

    target=$(sp_realpath "$label_path" || printf '%s\n' "$label_path")
    if [ -z "$target" ]; then
        sp_log "state=discover-config" \
            "phase=label" \
            "result=skip" \
            "reason=label-target-missing" \
            "path=${label_path}"
        return 1
    fi

    if sp_attempt_mount_candidate "$target" "label" "$SP_CONFIG_LABEL"; then
        return 0
    fi

    return 1
}

sp_should_skip_device() {
    base="$1"
    case "$base" in
        loop*|ram*|fd*|sr*|dm*)
            return 0
            ;;
    esac
    return 1
}

sp_try_removable_candidates() {
    if [ "${SP_CONFIG_SCAN_REMOVABLE_FALLBACK:-0}" != "1" ]; then
        sp_log "state=discover-config" "phase=removable" "result=skip" "reason=fallback-disabled"
        return 1
    fi

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

        removable="$(sp_parent_removable_value "$base" || echo "0")"
        if [ "$removable" != "1" ]; then
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
            sp_log "state=discover-config" "phase=removable" "result=discovered" "candidate=${candidate}"
            found=1
            if sp_attempt_mount_candidate "$candidate" "removable" "$part_base"; then
                return 0
            fi
        done
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

        removable="$(sp_parent_removable_value "$base" || echo "0")"
        if [ "$removable" != "1" ] && [ "${SP_CONFIG_ALLOW_NONREMOVABLE:-0}" != "1" ]; then
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

        removable="$(sp_parent_removable_value "$base" || echo "0")"
        if [ "$removable" != "1" ] && [ "${SP_CONFIG_ALLOW_NONREMOVABLE:-0}" != "1" ]; then
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
