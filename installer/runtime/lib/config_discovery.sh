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

SP_CONFIG_LABEL_NAME="${SP_CONFIG_LABEL_NAME:-SP_CONFIG}"
SP_CONFIG_LABEL_DIR="${SP_CONFIG_LABEL_DIR:-/dev/disk/by-label}"
SP_CONFIG_MOUNT_POINT="${SP_CONFIG_MOUNT_POINT:-/config}"
SP_CONFIG_FILE="${SP_CONFIG_FILE:-installer-config.yml}"
SP_CONFIG_DISCOVERY_MAX_ATTEMPTS="${SP_CONFIG_DISCOVERY_MAX_ATTEMPTS:-10}"
SP_CONFIG_DISCOVERY_SLEEP="${SP_CONFIG_DISCOVERY_SLEEP:-1}"

SP_CONFIG_DISCOVERY_ATTEMPTS_LOG=""
SP_CONFIG_DISCOVERY_ATTEMPT_COUNT=0

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

sp_mount_device() {
    candidate="$1"
    [ -n "$candidate" ] || return 1
    if [ ! -e "$candidate" ]; then
        return 1
    fi
    mkdir -p "$SP_CONFIG_MOUNT_POINT" 2>/dev/null || true
    mount -t vfat -o ro "$candidate" "$SP_CONFIG_MOUNT_POINT" >/dev/null 2>&1
}

sp_wait_for_udev() {
    if command -v udevadm >/dev/null 2>&1; then
        udevadm settle >/dev/null 2>&1 || true
    fi
}

sp_sleep_between_attempts() {
    value="${SP_CONFIG_DISCOVERY_SLEEP:-}"
    case "$value" in
        ''|*[!0-9]*)
            return
            ;;
    esac

    if [ "$value" -gt 0 ]; then
        sleep "$value"
    fi
}

sp_log_lsblk_diag() {
    if command -v lsblk >/dev/null 2>&1; then
        lsblk -f 2>/dev/null | while IFS= read -r line; do
            sp_log "state=discover-config" "source=lsblk" "line=${line:-}"
        done
    else
        sp_log "state=discover-config" "source=lsblk" "note=command-missing"
    fi
}

sp_log_blkid_diag() {
    if command -v blkid >/dev/null 2>&1; then
        blkid 2>/dev/null | while IFS= read -r line; do
            sp_log "state=discover-config" "source=blkid" "line=${line:-}"
        done
    else
        sp_log "state=discover-config" "source=blkid" "note=command-missing"
    fi
}

sp_attempt_mount_candidate() {
    candidate="$1"
    source="$2"
    label="$3"
    sp_cleanup_mount_point
    if sp_mount_device "$candidate"; then
        if [ -f "$SP_CONFIG_MOUNT_POINT/$SP_CONFIG_FILE" ]; then
            SP_CONFIG_PATH="$SP_CONFIG_MOUNT_POINT/$SP_CONFIG_FILE"
            export SP_CONFIG_PATH
            sp_log "state=discover-config" \
                "result=found" \
                "path=$SP_CONFIG_PATH" \
                "source=$source" \
                "candidate=$candidate" \
                "label=${label:-}"
            return 0
        fi
        reason="missing-config-file"
    else
        reason="mount-failed"
    fi

    sp_log "state=discover-config" \
        "candidate=$candidate" \
        "source=$source" \
        "label=${label:-}" \
        "result=reject" \
        "reason=$reason"
    sp_record_config_candidate "$candidate" "$reason" "$label"
    sp_unmount_config_point
    return 1
}

sp_try_label_candidate() {
    label_path="${SP_CONFIG_LABEL_DIR%/}/${SP_CONFIG_LABEL_NAME}"
    if [ ! -e "$label_path" ]; then
        sp_log "state=discover-config" "phase=label" "result=skip" "reason=label-missing" "path=$label_path"
        return 1
    fi

    sp_log "state=discover-config" "phase=label" "result=attempt" "path=$label_path"
    sp_attempt_mount_candidate "$label_path" "label" "$SP_CONFIG_LABEL_NAME"
}

sp_scan_vfat_candidates() {
    if ! command -v blkid >/dev/null 2>&1; then
        sp_log "state=discover-config" "phase=scan" "result=skip" "reason=blkid-missing"
        return 1
    fi

    blkid_output="$(blkid -t TYPE=vfat -o export 2>/dev/null || true)"
    if [ -z "$blkid_output" ]; then
        sp_log "state=discover-config" "phase=scan" "result=skip" "reason=no-vfat-candidates"
        return 1
    fi

    candidate_dev=""
    candidate_label=""
    while IFS= read -r line; do
        if [ -z "$line" ]; then
            if [ -n "$candidate_dev" ]; then
                sp_log "state=discover-config" \
                    "phase=scan" \
                    "result=discovered" \
                    "candidate=$candidate_dev" \
                    "label=${candidate_label:-unknown}"
                if sp_attempt_mount_candidate "$candidate_dev" "scan" "$candidate_label"; then
                    return 0
                fi
            fi
            candidate_dev=""
            candidate_label=""
            continue
        fi

        case "$line" in
            DEVNAME=*)
                candidate_dev="${line#DEVNAME=}"
                ;;
            LABEL=*)
                candidate_label="${line#LABEL=}"
                ;;
        esac
    done <<EOF
$blkid_output
EOF

    if [ -n "$candidate_dev" ]; then
        sp_log "state=discover-config" \
            "phase=scan" \
            "result=discovered" \
            "candidate=$candidate_dev" \
            "label=${candidate_label:-unknown}"
        if sp_attempt_mount_candidate "$candidate_dev" "scan" "$candidate_label"; then
            return 0
        fi
    fi

    return 1
}

sp_discover_config() {
    SP_CONFIG_DISCOVERY_ATTEMPTS_LOG=""
    SP_CONFIG_DISCOVERY_ATTEMPT_COUNT=0
    sp_log "state=discover-config" "phase=start"

    max_attempts="${SP_CONFIG_DISCOVERY_MAX_ATTEMPTS:-10}"
    case "$max_attempts" in
        ''|*[!0-9]*)
            max_attempts=10
            ;;
    esac
    if [ "$max_attempts" -lt 1 ]; then
        max_attempts=1
    fi

    attempt=1
    while [ "$attempt" -le "$max_attempts" ]; do
        sp_log "state=discover-config" "phase=attempt" "number=$attempt"

        if sp_try_label_candidate; then
            return 0
        fi

        if sp_scan_vfat_candidates; then
            return 0
        fi

        if [ "$attempt" -lt "$max_attempts" ]; then
            sp_sleep_between_attempts
        fi

        attempt=$((attempt + 1))
    done

    sp_wait_for_udev
    sp_log "state=discover-config" \
        "result=not-found" \
        "attempts=$SP_CONFIG_DISCOVERY_ATTEMPT_COUNT"
    sp_log_lsblk_diag
    sp_log_blkid_diag
    sp_log_candidate_summary
    sp_enter_rescue_mode "missing-config"
    return 1
}
