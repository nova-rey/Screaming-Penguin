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
    # shellcheck disable=SC1091
    # shellcheck source=installer/runtime/lib/rescue_mode.sh
    . "$SP_RESCUE_MODE_LIB"
fi

SP_STORAGE_BOOTSTRAP_LIB="$SP_RUNTIME_LIB_DIR/storage_bootstrap.sh"
if [ -f "$SP_STORAGE_BOOTSTRAP_LIB" ]; then
    # shellcheck disable=SC1091
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
SP_CONFIG_LABEL_DIR="${SP_CONFIG_LABEL_DIR:-/dev/disk/by-label}"
SP_CONFIG_REQUIRE_BY_LABEL="${SP_CONFIG_REQUIRE_BY_LABEL:-0}"
SP_CONFIG_FILE="${SP_CONFIG_FILE:-installer-config.yml}"
SP_SYS_BLOCK_ROOT="${SP_SYS_BLOCK_ROOT:-/sys/block}"
SP_DEV_ROOT="${SP_DEV_ROOT:-/dev}"
SP_PROC_PARTITIONS="${SP_PROC_PARTITIONS:-/proc/partitions}"
SP_CONFIG_DISCOVERY_MAX_ATTEMPTS="${SP_CONFIG_DISCOVERY_MAX_ATTEMPTS:-1}"
SP_CONFIG_DISCOVERY_EXCLUDE_PREFIXES="${SP_CONFIG_DISCOVERY_EXCLUDE_PREFIXES:-loop ram fd sr dm}"
SP_CONFIG_LABEL_PROBE_CANDIDATES=0
SP_CONFIG_LABEL_DEVICE=""
SP_CONFIG_LABEL_BLKID_FAILURE=0
SP_LAST_LABEL_PROBE_LABEL=""

SP_CONFIG_DISCOVERY_ATTEMPTS_LOG=""
SP_CONFIG_DISCOVERY_ATTEMPT_COUNT=0
SP_CONFIG_DISCOVERY_TRIED=""
SP_CONFIG_FS_TYPES="${SP_CONFIG_FS_TYPES:-vfat}"
SP_CONFIG_FS_TYPES_ORDERED=""
SP_CONFIG_FS_TYPES_SERIALIZED=""
SP_CONFIG_MOUNT_TRIED_VFAT=0
export SP_CONFIG_MOUNT_TRIED_VFAT
SP_CONFIG_LAST_VFAT_MOUNT_OUTPUT=""
export SP_CONFIG_LAST_VFAT_MOUNT_OUTPUT
SP_CONFIG_LAST_VFAT_MOUNT_OUTPUT=""

sp_trim_spaces() {
    printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

sp_build_config_fs_types() {
    raw="${SP_CONFIG_FS_TYPES:-vfat}"
    normalized="$(printf '%s' "$raw" | tr ',' ' ')"
    ordered=""
    serialized=""
    for entry in $normalized; do
        trimmed="$(sp_trim_spaces "$entry" || true)"
        if [ -z "$trimmed" ]; then
            continue
        fi
        if [ -z "$ordered" ]; then
            ordered="$trimmed"
            serialized="$trimmed"
        else
            ordered="${ordered} ${trimmed}"
            serialized="${serialized},${trimmed}"
        fi
    done
    if [ -z "$ordered" ]; then
        ordered="vfat"
        serialized="vfat"
    fi
    SP_CONFIG_FS_TYPES_ORDERED="$ordered"
    SP_CONFIG_FS_TYPES_SERIALIZED="$serialized"
}

sp_build_config_fs_types

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

sp_handle_by_label_failure() {
    log_device="${SP_LOG_DEVICE:-/dev/console}"
    printf '[SP-INSTALLER][FATAL] by-label namespace empty after population\n' >>"$log_device" 2>&1 || true
    sp_enter_rescue_mode "by-label-empty"
}

sp_log_by_label_warn() {
    printf '[SP-INSTALLER][WARN] %s\n' "$1" >&2
}

sp_has_blkid() {
    blkid_path="$(command -v blkid 2>/dev/null || true)"
    if [ -z "$blkid_path" ]; then
        return 1
    fi

    "$blkid_path" --version >/dev/null 2>&1
}

sp_probe_label_with_blkid() {
    device="$1"
    if [ -z "$device" ]; then
        return 1
    fi

    if ! sp_has_blkid; then
        return 127
    fi

    if blkid_output="$(blkid -o export "$device" 2>&1)"; then
        rc=0
    else
        rc=$?
    fi

    SP_LAST_LABEL_PROBE_LABEL=""
    label_value=""
    current_dev=""
    while IFS= read -r line; do
        case "$line" in
            DEVNAME=*)
                current_dev="${line#DEVNAME=}"
                ;;
            LABEL=*)
                label_value="${line#LABEL=}"
                if [ -n "$current_dev" ] && [ "$current_dev" != "$device" ] && [ "$current_dev" != "${device##*/}" ]; then
                    label_value=""
                    continue
                fi
                break
                ;;
        esac
    done <<__BLKID_EXPORT__
$blkid_output
__BLKID_EXPORT__

    sp_log "label-probe" \
        "device=${device}" \
        "rc=${rc}" \
        "label=${label_value:-}"

    if [ "$rc" -ne 0 ]; then
        case "$rc" in
            126|127)
                return "$rc"
                ;;
        esac
    fi

    SP_LAST_LABEL_PROBE_LABEL="${label_value:-}"
    return 0
}

sp_find_partition_by_fs_label() {
    label="$1"
    partitions="${SP_PROC_PARTITIONS:-/proc/partitions}"
    SP_CONFIG_LABEL_PROBE_CANDIDATES=0
    SP_CONFIG_LABEL_DEVICE=""

    if [ -z "$label" ]; then
        return 1
    fi

    if [ ! -r "$partitions" ]; then
        return 1
    fi

    if ! sp_has_blkid; then
        return 2
    fi

    candidate_count=0
    while IFS= read -r line; do
        read -r major _ _ name _ <<__PARTITION_LINE__
$line
__PARTITION_LINE__
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

        partition_base=""
        if [ -d "$SP_SYS_BLOCK_ROOT" ]; then
            for block_dir in "$SP_SYS_BLOCK_ROOT"/*; do
                if [ ! -d "$block_dir" ]; then
                    continue
                fi
                if [ -d "$block_dir/$name" ] && [ -f "$block_dir/$name/partition" ]; then
                    partition_base="$(basename "$block_dir")"
                    break
                fi
            done
        fi

        if [ -z "$partition_base" ]; then
            partition_base="${name}"
        fi

        if sp_should_skip_device "$partition_base"; then
            continue
        fi

        candidate_count=$((candidate_count + 1))
        SP_CONFIG_LABEL_PROBE_CANDIDATES="$candidate_count"

        if sp_probe_label_with_blkid "$candidate"; then
            if [ "${SP_LAST_LABEL_PROBE_LABEL:-}" = "$label" ]; then
                SP_CONFIG_LABEL_DEVICE="$candidate"
                return 0
            fi
            continue
        fi

        return 2
    done < "$partitions"

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

    fat_modules_attempted=0
    tried=""
    last_rc=1
    last_error=""
    SP_CONFIG_LAST_VFAT_MOUNT_OUTPUT=""

    for fs in $SP_CONFIG_FS_TYPES_ORDERED; do
        if [ "$fs" = "vfat" ] && [ "$fat_modules_attempted" -eq 0 ]; then
            sp_try_load_fat_stack
            fat_modules_attempted=1
        fi

        if mount_output="$(mount -o ro -t "$fs" "$candidate" "$SP_CONFIG_MOUNT_POINT" 2>&1)"; then
            sp_log "config-mount-ok" "fstype=${fs}" "dev=${candidate}" "mnt=${SP_CONFIG_MOUNT_POINT}"
            return 0
        fi

        mount_rc=$?
        last_rc="$mount_rc"
        last_error="$(printf '%s' "$mount_output" | tr '\n' ' ' || true)"
        if [ -z "$tried" ]; then
            tried="$fs"
        else
            tried="${tried},${fs}"
        fi
        if [ "$fs" = "vfat" ]; then
            SP_CONFIG_MOUNT_TRIED_VFAT=1
            SP_CONFIG_LAST_VFAT_MOUNT_OUTPUT="$mount_output"
        fi
    done

    tried="${tried:-${SP_CONFIG_FS_TYPES_SERIALIZED:-vfat}}"
    error="${last_error:-none}"
    sp_log_fatal_marker "config-mount-failed dev=${candidate} tried=${tried} last_rc=${last_rc} error=${error}"
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
    SP_CONFIG_LABEL_BLKID_FAILURE=0

    label_dir="${SP_CONFIG_LABEL_DIR:-}"
    if [ -n "$label_dir" ] && [ -d "$label_dir" ]; then
        label_node="${label_dir%/}/${SP_CONFIG_LABEL_NAME}"
        if [ -e "$label_node" ]; then
            resolved_label="$(sp_realpath "$label_node" || printf '%s\n' "$label_node")"
            SP_CONFIG_LABEL_DEVICE="${resolved_label:-}"
            sp_log "SP_CONFIG_LABEL_DEVICE=${SP_CONFIG_LABEL_DEVICE:-}"
            if sp_attempt_mount_candidate "$SP_CONFIG_LABEL_DEVICE" "label" "$SP_CONFIG_LABEL_NAME"; then
                return 0
            fi
            SP_CONFIG_LABEL_DEVICE=""
        fi
    fi

    probe_result=0
    if sp_find_partition_by_fs_label "$SP_CONFIG_LABEL_NAME"; then
        target="${SP_CONFIG_LABEL_DEVICE:-}"
        sp_log "SP_CONFIG_LABEL_DEVICE=${target:-}"
        if [ -n "$target" ] && sp_attempt_mount_candidate "$target" "label" "$SP_CONFIG_LABEL_NAME"; then
            return 0
        fi
        return 1
    else
        probe_result=$?
    fi

    if [ "${probe_result:-0}" -eq 2 ] && [ "${SP_CONFIG_LABEL_REQUESTED:-0}" -eq 1 ]; then
        SP_CONFIG_LABEL_BLKID_FAILURE=1
        sp_log_fatal_marker "missing-blkid-for-label-probe label=${SP_CONFIG_LABEL_NAME}"
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

    by_label_dir="${SP_CONFIG_LABEL_DIR:-/dev/disk/by-label}"
    if [ ! -d "$by_label_dir" ]; then
        if [ "${SP_CONFIG_REQUIRE_BY_LABEL:-0}" = "1" ]; then
            sp_handle_by_label_failure
            return 1
        fi
        sp_log_by_label_warn "by-label namespace missing; continuing fallback discovery"
    else
        if [ -z "$(ls -A "$by_label_dir" 2>/dev/null || true)" ]; then
            if [ "${SP_CONFIG_REQUIRE_BY_LABEL:-0}" = "1" ]; then
                sp_handle_by_label_failure
                return 1
            fi
            sp_log_by_label_warn "by-label namespace empty after population; continuing fallback discovery"
        fi
    fi

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
            if [ "${SP_CONFIG_LABEL_BLKID_FAILURE:-0}" -eq 0 ]; then
                sp_log_fatal_marker "label-not-found label=${SP_CONFIG_LABEL_NAME} probed=${SP_CONFIG_LABEL_PROBE_CANDIDATES:-0}"
            fi
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
