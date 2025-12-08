#!/bin/sh
# shellcheck shell=dash

# Minimal, POSIX-friendly bootstrap for the installer initramfs.

SP_LOG_DEVICE="${SP_LOG_DEVICE:-/dev/console}"
SP_WRITE_GATE_SERIAL_DEVICE="${SP_WRITE_GATE_SERIAL_DEVICE:-/dev/ttyS0}"

sp_log() {
    # Simple structured logger. All lines should start with [SP-INSTALLER].
    # Usage: sp_log "key=value" "message=..."
    printf '[SP-INSTALLER] %s\n' "$@" >>"$SP_LOG_DEVICE" 2>&1
}

sp_trim() {
    printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

sp_write_gate_serial_log() {
    serial_device="${SP_WRITE_GATE_SERIAL_DEVICE:-}"
    if [ -n "$serial_device" ]; then
        printf '%s\n' "$1" >>"$serial_device" 2>/dev/null || true
    fi
}

sp_log_write_gate_marker() {
    printf '[SP-INSTALLER] %s\n' "$1" >>"$SP_LOG_DEVICE" 2>&1 || true
    sp_write_gate_serial_log "[SP-INSTALLER] $1"
}

SP_INIT_SCRIPT_PATH="${SP_INIT_SCRIPT_PATH:-$0}"
SP_SCRIPT_DIR="$(cd "$(dirname "$SP_INIT_SCRIPT_PATH")" && pwd)"
SP_RUNTIME_LIB_DIR="$(cd "$SP_SCRIPT_DIR/../runtime/lib" && pwd)"
SP_DISK_LAYOUT_LIB="$SP_RUNTIME_LIB_DIR/disk_layout.sh"
SP_DISK_EXECUTE_LIB="$SP_RUNTIME_LIB_DIR/disk_execute.sh"

if [ -f "$SP_DISK_LAYOUT_LIB" ]; then
    # shellcheck disable=SC1090
    # shellcheck source=installer/runtime/lib/disk_layout.sh
    . "$SP_DISK_LAYOUT_LIB"
fi

if [ -f "$SP_DISK_EXECUTE_LIB" ]; then
    # shellcheck disable=SC1090
    # shellcheck source=installer/runtime/lib/disk_execute.sh
    . "$SP_DISK_EXECUTE_LIB"
fi

sp_write_gate_blocked() {
    reason="$1"
    sp_log "state=write-gate" "result=blocked" "reason=$reason"
    sp_log_write_gate_marker "write-gate BLOCKED"
    sp_write_gate_serial_log "[SP-INSTALLER] write-gate BLOCKED reason=$reason"
}

sp_write_gate_ok() {
    sp_log "state=write-gate" "result=ok"
    sp_log_write_gate_marker "write-gate OK"
}

sp_parse_write_gate_bool() {
    line="$1"
    value=${line#*:}
    value=$(sp_trim "$value")
    value=${value%%#*}
    value=$(sp_trim "$value")

    # strip surrounding quotes if present
    while [ "${value#\"}" != "$value" ]; do
        value=${value#\"}
    done
    while [ "${value%\"}" != "$value" ]; do
        value=${value%\"}
    done
    while [ "${value#\'}" != "$value" ]; do
        value=${value#\'}
    done
    while [ "${value%\'}" != "$value" ]; do
        value=${value%\'}
    done

    if [ -z "$value" ]; then
        return 1
    fi

    case "$value" in
        true|True|TRUE|yes|YES|on|1)
            printf 'true'
            return 0
            ;;
        false|False|FALSE|no|NO|off|0)
            printf 'false'
            return 0
            ;;
        *)
            return 2
            ;;
    esac
}


sp_find_write_gate_line() {
    awk '
    BEGIN {
        installer_indent = -1
        found = 0
    }
    /^[[:space:]]*installer[[:space:]]*:/ {
        match($0, /^[[:space:]]*/)
        installer_indent = RLENGTH
        next
    }
    {
        if (installer_indent < 0) {
            next
        }

        if ($0 ~ /^[[:space:]]*$/) {
            next
        }
        if ($0 ~ /^[[:space:]]*#/) {
            next
        }

        match($0, /^[[:space:]]*/)
        if (RLENGTH <= installer_indent) {
            exit
        }

        if ($0 ~ /^[[:space:]]*write_gate[[:space:]]*:/) {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            sub(/#.*/, "", line)
            print line
            found = 1
            exit
        }
    }
    END {
        if (found == 0) {
            exit 1
        }
    }
    ' "$SP_CONFIG_PATH"
}
sp_enforce_write_gate() {
    if [ -z "${SP_CONFIG_PATH:-}" ]; then
        sp_write_gate_blocked "missing-config-path"
        return 1
    fi

    if ! write_gate_line=$(sp_find_write_gate_line); then
        sp_write_gate_blocked "installer.write_gate not defined"
        return 1
    fi

    gate_value=$(sp_parse_write_gate_bool "$write_gate_line")
    gate_status=$?

    if [ "$gate_status" -eq 2 ]; then
        sp_write_gate_blocked "installer.write_gate has invalid value"
        return 1
    fi

    if [ "$gate_status" -ne 0 ]; then
        sp_write_gate_blocked "installer.write_gate value missing"
        return 1
    fi

    if [ "$gate_value" != "true" ]; then
        sp_write_gate_blocked "installer.write_gate disabled"
        return 1
    fi

    sp_write_gate_ok
    return 0
}

sp_dev_to_base() {
    dev_path="$1"
    dev_path="${dev_path#/dev/}"
    # Just echo the part after /dev/; caller decides how to interpret.
    printf '%s\n' "$dev_path"
}

sp_is_block_device() {
    dev="$1"

    [ -n "$dev" ] || return 1

    case "$dev" in
        /dev/*)
            [ -b "$dev" ] && return 0
            ;;
        *)
            if [ -b "/dev/$dev" ]; then
                return 0
            fi
            ;;
    esac

    return 1
}

sp_bootstrap() {
    PATH=/bin:/sbin:/usr/bin:/usr/sbin
    export PATH

    # BusyBox setup (best-effort).
    if [ -x /bin/busybox ]; then
        /bin/busybox --install -s /bin 2>/dev/null || true
    fi

    # Minimal mounts (best-effort, do not hard-fail).
    mount -t proc proc /proc 2>/dev/null || true
    mount -t sysfs sysfs /sys 2>/dev/null || true
    mount -t devtmpfs devtmpfs /dev 2>/dev/null || \
        mount -t tmpfs devtmpfs /dev 2>/dev/null || true

    sp_log 'marker=init-reached' 'msg=init reached'
    # CI marker required by qemu_smoke_ci.sh (must remain exact).
    echo "[SP-INSTALLER] init reached" >/dev/console

    # Stage 1 breadcrumb for future debugging (not enforced by CI yet).
    sp_log 'stage=bootstrapped'
}

sp_detect_mode() {
    source="default"

    if [ -n "${SP_MODE:-}" ]; then
        case "$SP_MODE" in
            SMOKE|INSTALL)
                source="env"
                ;;
            *)
                SP_MODE="SMOKE"
                source="default"
                ;;
        esac
    else
        mode_candidate=""

        if [ -r /proc/cmdline ]; then
            if read -r cmdline < /proc/cmdline; then
                for token in $cmdline; do
                    case "$token" in
                        sp.mode=*)
                            mode_candidate=${token#sp.mode=}
                            ;;
                    esac
                done
            fi
        fi

        case "$mode_candidate" in
            SMOKE|INSTALL)
                SP_MODE="$mode_candidate"
                source="kernel"
                ;;
            *)
                SP_MODE="SMOKE"
                source="default"
                ;;
        esac
    fi

    export SP_MODE
    sp_log "state=mode-detect" "mode=$SP_MODE" "source=$source"
}

sp_discover_config() {
    # returns 0 if config found, non-zero otherwise
    # sets SP_CONFIG_PATH on success
    SP_CONFIG_PATH=""
    CONFIG_CANDIDATES="/config/installer-config.yml /mnt/config/installer-config.yml"

    for p in $CONFIG_CANDIDATES; do
        if [ -f "$p" ]; then
            SP_CONFIG_PATH=$p
            export SP_CONFIG_PATH
            sp_log "state=discover-config" "result=found" "path=$SP_CONFIG_PATH"
            return 0
        fi
    done

    unset SP_CONFIG_PATH
    sp_log "state=discover-config" "result=not-found"
    return 1
}

sp_parse_config_minimal() {
    target_disk_found=0

    while IFS= read -r line || [ -n "$line" ]; do
        trimmed=$(printf '%s' "$line" | sed 's/^[[:space:]]*//')

        case "$trimmed" in
            ""|"#"*)
                continue
                ;;
            target_disk:*)
                value=${trimmed#target_disk:}
                value_no_comment=${value%%#*}
                value_clean=$(printf '%s' "$value_no_comment" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

                case "$value_clean" in
                    "\"*\"")
                        value_clean=${value_clean#"\""}
                        value_clean=${value_clean%"\""}
                        ;;
                    "'*'")
                        value_clean=${value_clean#"'"}
                        value_clean=${value_clean%"'"}
                        ;;
                esac

                value_clean=$(printf '%s' "$value_clean" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

                if [ -n "$value_clean" ]; then
                    SP_TARGET_DISK=$value_clean
                    SP_CONFIG_HAS_TARGET_DISK=1
                    export SP_TARGET_DISK SP_CONFIG_HAS_TARGET_DISK
                    sp_log "state=config-load" "key=target_disk" "value=$SP_TARGET_DISK" "result=parsed"
                    target_disk_found=1
                else
                    sp_log "state=config-load" "key=target_disk" "result=missing-or-invalid"
                    return 1
                fi
                ;;
        esac
    done < "$SP_CONFIG_PATH"

    if [ "$target_disk_found" -ne 1 ]; then
        sp_log "state=config-load" "key=target_disk" "result=missing-or-invalid"
        return 1
    fi

    return 0
}

sp_load_config() {
    # Precondition: SP_CONFIG_PATH may be set or unset.
    if [ -z "${SP_CONFIG_PATH:-}" ]; then
        sp_log "state=config-load" "result=skip" "reason=no-config-path"
        return 0
    fi

    if [ ! -r "$SP_CONFIG_PATH" ]; then
        sp_log "state=config-load" "result=error" "reason=unreadable" "path=$SP_CONFIG_PATH"
        return 1
    fi

    sp_log "state=config-load" "phase=start" "path=$SP_CONFIG_PATH"

    if ! sp_parse_config_minimal; then
        sp_log "state=config-load" "phase=done" "result=error"
        return 1
    fi

    sp_log "state=config-load" "phase=done" "result=ok"
    return 0
}

sp_resolve_target_disk() {
    SP_TARGET_KIND=""

    if [ -z "${SP_TARGET_DISK:-}" ]; then
        sp_log "state=config-resolve" "result=skip" "reason=no-target-disk"
        unset SP_TARGET_KIND
        return 0
    fi

    dev_path="$SP_TARGET_DISK"
    base=$(sp_dev_to_base "$dev_path")

    if [ -z "$base" ]; then
        sp_log "state=config-resolve" "result=error" "reason=empty-base" "target=$SP_TARGET_DISK"
        unset SP_TARGET_KIND
        return 1
    fi

    if [ -d "/sys/block/$base" ]; then
        kind="disk"
    elif [ -d "/sys/block/${base%%[0-9]*}/$base" ]; then
        kind="partition"
    else
        sp_log "state=config-resolve" "result=error" "reason=not-found-in-sysfs" "target=$SP_TARGET_DISK"
        unset SP_TARGET_KIND
        return 1
    fi

    SP_TARGET_KIND="$kind"
    export SP_TARGET_KIND
    sp_log "state=config-resolve" "result=ok" "kind=$kind" "target=$SP_TARGET_DISK"
    return 0
}

sp_disk_size_bytes() {
    base="$1"
    if [ -z "$base" ] || [ ! -r "/sys/block/$base/size" ]; then
        return 1
    fi

    sectors=$(cat "/sys/block/$base/size" 2>/dev/null || echo "")
    if [ -z "$sectors" ]; then
        return 1
    fi

    awk -v s="$sectors" 'BEGIN { printf "%d\n", s * 512 }'
}

sp_probe_disks() {
    sp_log "state=probe-disks" "phase=start"

    if [ ! -d /sys/block ]; then
        sp_log "state=probe-disks" "error=no-sys-block"
        return 1
    fi

    EXCLUDE_PREFIXES="loop ram fd sr dm"

    for dev in /sys/block/*; do
        base=$(basename "$dev")

        skip=false
        for pfx in $EXCLUDE_PREFIXES; do
            case "$base" in
                "$pfx"*)
                    skip=true
                    ;;
            esac
        done

        if [ "$skip" = true ]; then
            continue
        fi

        size_file="$dev/size"
        sectors="unknown"
        if [ -r "$size_file" ]; then
            sectors=$(cat "$size_file" 2>/dev/null || echo "unknown")
        fi

        removable_file="$dev/removable"
        removable="unknown"
        if [ -r "$removable_file" ]; then
            removable=$(cat "$removable_file" 2>/dev/null || echo "unknown")
        fi

        sp_log "state=probe-disks" "kind=disk" "name=$base" "sectors=$sectors" "removable=$removable"

        for part in "$dev"/*; do
            [ -e "$part" ] || continue
            part_base=$(basename "$part")

            case "$part_base" in
                "$base"*)
                    :
                    ;;
                *)
                    continue
                    ;;
            esac

            part_size_file="$part/size"
            part_sectors="unknown"
            if [ -r "$part_size_file" ]; then
                part_sectors=$(cat "$part_size_file" 2>/dev/null || echo "unknown")
            fi

            sp_log "state=probe-disks" "kind=partition" "name=$part_base" "sectors=$part_sectors"
        done
    done

    if command -v lsblk >/dev/null 2>&1; then
        # Supplemental diagnostic output; best-effort only.
        lsblk -ndo NAME,SIZE,TYPE,MODEL 2>/dev/null | while IFS= read -r line; do
            sp_log "state=probe-disks" "source=lsblk" "line=$line"
        done
    fi

    sp_log "state=probe-disks" "phase=done"
    return 0
}

sp_plan_partitioning() {
    if [ -z "${SP_TARGET_DISK:-}" ]; then
        sp_log "state=plan-partitioning" "result=skip" "reason=no-target-disk"
        return 0
    fi

    if [ "${SP_TARGET_KIND:-disk}" != "disk" ]; then
        sp_log "state=plan-partitioning" "result=skip" "reason=target-not-disk" "target=$SP_TARGET_DISK" "kind=${SP_TARGET_KIND:-unknown}"
        return 0
    fi

    base=$(sp_dev_to_base "$SP_TARGET_DISK")
    if [ -z "$base" ]; then
        sp_log "state=plan-partitioning" "result=error" "reason=empty-base" "target=$SP_TARGET_DISK"
        return 1
    fi

    size_bytes=$(sp_disk_size_bytes "$base" || echo "")
    if [ -z "$size_bytes" ]; then
        sp_log "state=plan-partitioning" "result=error" "reason=disk-size-unavailable" "target=$SP_TARGET_DISK"
        return 1
    fi

    efi_size_mib=512

    root_size_mib=$(awk -v bytes="$size_bytes" -v efi="$efi_size_mib" '
        BEGIN {
            mib = bytes / (1024.0 * 1024.0);
            guard = 4;
            root = int(mib - efi - guard);
            if (root < 0) root = 0;
            printf "%d\n", root;
        }
    ')

    part1_name="$base"1
    part2_name="$base"2

    case "$base" in
        nvme*|mmcblk*)
            part1_name="${base}p1"
            part2_name="${base}p2"
            ;;
    esac

    sp_log "state=plan-partitioning" \
        "result=ok" \
        "target=$SP_TARGET_DISK" \
        "table=gpt" \
        "disk_bytes=$size_bytes" \
        "efi_size_mib=$efi_size_mib" \
        "root_size_mib=$root_size_mib" \
        "efi_part=/dev/$part1_name" \
        "root_part=/dev/$part2_name" \
        "note=dry-run-no-changes"

    return 0
}

sp_disk_layout_debug_plan() {
    if [ "${SP_DEBUG_DISK_LAYOUT:-0}" != "1" ]; then
        return 0
    fi

    sp_log "state=disk-layout" "marker=plan-start"
    sp_write_gate_serial_log "[SP-INSTALLER] disk-layout plan START"

    if ! sp_print_layout_plan ""; then
        sp_log "state=disk-layout" "result=failed" "reason=planner-exit"
        sp_write_gate_serial_log "[SP-INSTALLER] disk-layout plan FAILED"
        return 1
    fi

    plan="${SP_DISK_LAYOUT_LAST_PLAN:-}"
    if [ -n "$plan" ]; then
        printf '%s\n' "$plan" | while IFS= read -r line; do
            sp_write_gate_serial_log "[SP-INSTALLER] disk-layout plan BODY $line"
        done
    fi

    sp_write_gate_serial_log "[SP-INSTALLER] disk-layout plan END"
    sp_log "state=disk-layout" "marker=plan-end"

    return 0
}

sp_idle_shell() {
    sp_log "state=idle-shell" "msg=waiting-for-next-stage"
    exec sh -i </dev/console >/dev/console 2>&1
}

sp_can_modify_disk() {
    case "${SP_MODE:-SMOKE}" in
        INSTALL)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

sp_readiness_smoke() {
    sp_log "state=readiness" \
        "mode=SMOKE" \
        "result=ok" \
        "reason=smoke-mode-no-writes"

    return 0
}

sp_readiness_install() {
    if [ -z "${SP_CONFIG_PATH:-}" ]; then
        sp_log "state=readiness" \
            "mode=INSTALL" \
            "result=error" \
            "reason=missing-config" \
            "config=${SP_CONFIG_PATH:-none}" \
            "target=${SP_TARGET_DISK:-none}" \
            "target_kind=${SP_TARGET_KIND:-unknown}"
        return 1
    fi

    if [ -z "${SP_TARGET_DISK:-}" ]; then
        sp_log "state=readiness" \
            "mode=INSTALL" \
            "result=error" \
            "reason=missing-target" \
            "config=${SP_CONFIG_PATH:-none}" \
            "target=${SP_TARGET_DISK:-none}" \
            "target_kind=${SP_TARGET_KIND:-unknown}"
        return 1
    fi

    if ! sp_is_block_device "$SP_TARGET_DISK"; then
        sp_log "state=readiness" \
            "mode=INSTALL" \
            "result=error" \
            "reason=invalid-target" \
            "config=${SP_CONFIG_PATH:-none}" \
            "target=${SP_TARGET_DISK:-none}" \
            "target_kind=${SP_TARGET_KIND:-unknown}"
        return 1
    fi

    if [ -z "${SP_TARGET_KIND:-}" ] || [ "${SP_TARGET_KIND}" = "unknown" ]; then
        sp_log "state=readiness" \
            "mode=INSTALL" \
            "result=error" \
            "reason=unknown-target-kind" \
            "config=${SP_CONFIG_PATH:-none}" \
            "target=${SP_TARGET_DISK:-none}" \
            "target_kind=${SP_TARGET_KIND:-unknown}"
        return 1
    fi

    sp_log "state=readiness" \
        "mode=INSTALL" \
        "result=ok" \
        "config=${SP_CONFIG_PATH:-none}" \
        "target=${SP_TARGET_DISK:-none}" \
        "target_kind=${SP_TARGET_KIND:-unknown}"

    return 0
}

sp_check_readiness() {
    mode="${SP_MODE:-SMOKE}"

    case "$mode" in
        INSTALL)
            sp_readiness_install
            ;;
        *)
            sp_readiness_smoke
            ;;
    esac
}

sp_summary() {
    mode="${SP_MODE:-SMOKE}"
    config="${SP_CONFIG_PATH:-none}"
    target="${SP_TARGET_DISK:-none}"
    kind="${SP_TARGET_KIND:-unknown}"

    sp_log "state=summary" \
        "mode=$mode" \
        "config=$config" \
        "target=$target" \
        "target_kind=$kind"
}

main() {
    sp_bootstrap

    sp_detect_mode || true

    if [ "${SP_SKIP_CONFIG_DISCOVERY:-}" != "1" ]; then
        sp_discover_config || true
    else
        sp_log "state=discover-config" "result=skipped" "reason=skip-env"
    fi

    if ! sp_load_config; then
        sp_log "state=config-load" "result=error" "severity=non-fatal"
    fi

    if ! sp_enforce_write_gate; then
        exit 1
    fi

    if ! sp_resolve_target_disk; then
        sp_log "state=config-resolve" "result=error" "severity=non-fatal"
    fi

    if ! sp_probe_disks; then
        sp_log "state=probe-disks" "result=failed" "severity=non-fatal"
    fi

    if ! sp_plan_partitioning; then
        sp_log "state=plan-partitioning" "result=failed" "severity=non-fatal"
    fi

    if [ "${SP_DEBUG_DISK_LAYOUT:-0}" = "1" ]; then
        if ! sp_disk_layout_debug_plan; then
            sp_log "state=disk-layout" "result=failed" "note=debug-plan"
            exit 1
        fi
    fi

    sp_summary || true

    # Evaluate readiness for the current mode (no writes performed here).
    readiness_ok=0
    if sp_check_readiness; then
        readiness_ok=1
        sp_log "state=readiness-dispatch" \
            "mode=${SP_MODE:-SMOKE}" \
            "result=ready" \
            "note=writes-still-disabled-in-this-build"
    else
        readiness_ok=0
        sp_log "state=readiness-dispatch" \
            "mode=${SP_MODE:-SMOKE}" \
            "result=not-ready" \
            "note=installer-will-not-proceed-with-writes-in-this-build"
    fi

    disk_exec_reason=""
    if [ "${SP_ENABLE_DISK_EXECUTE:-0}" != "1" ]; then
        disk_exec_reason="toggle-disabled"
    elif [ "${SP_MODE:-SMOKE}" != "INSTALL" ]; then
        disk_exec_reason="not-install-mode"
    elif [ "${readiness_ok:-0}" != "1" ]; then
        disk_exec_reason="readiness-failed"
    elif [ "${SP_SKIP_CONFIG_DISCOVERY:-}" = "1" ]; then
        disk_exec_reason="skip-config-discovery"
    elif [ "${SP_EXIT_AFTER_INIT:-}" = "1" ]; then
        disk_exec_reason="exit-after-init"
    fi

    if [ -z "$disk_exec_reason" ]; then
        if ! sp_execute_gpt_plan; then
            sp_log "state=disk-exec" "result=failed" "target=${SP_TARGET_DISK:-none}"
            exit 1
        fi
    else
        sp_log "state=disk-exec" \
            "result=skipped" \
            "reason=$disk_exec_reason" \
            "target=${SP_TARGET_DISK:-none}"
    fi

    case "${SP_MODE:-SMOKE}" in
        INSTALL)
            sp_log "state=mode-dispatch" \
                "mode=INSTALL" \
                "result=not-implemented" \
                "note=install-write-path-disabled-in-this-build"
            ;;
        *)
            sp_log "state=mode-dispatch" \
                "mode=${SP_MODE:-SMOKE}" \
                "result=ok" \
                "note=smoke-mode-no-writes"
            ;;
    esac

    if [ "${SP_EXIT_AFTER_INIT:-}" = "1" ]; then
        sp_log "state=idle-shell" "msg=exit-after-init-env"
        exit 0
    fi

    sp_idle_shell
}

if [ "${SP_SKIP_INIT_MAIN:-0}" != "1" ]; then
    main "$@"
fi
