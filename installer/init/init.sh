#!/bin/sh
# shellcheck shell=dash

# Minimal, POSIX-friendly bootstrap for the installer initramfs.

sp_log() {
    # Simple structured logger. All lines should start with [SP-INSTALLER].
    # Usage: sp_log "key=value" "message=..."
    printf '[SP-INSTALLER] %s\n' "$@" >/dev/console 2>&1
}

sp_dev_to_base() {
    dev_path="$1"
    dev_path="${dev_path#/dev/}"
    # Just echo the part after /dev/; caller decides how to interpret.
    printf '%s\n' "$dev_path"
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

sp_idle_shell() {
    sp_log "state=idle-shell" "msg=waiting-for-next-stage"
    exec sh -i </dev/console >/dev/console 2>&1
}

main() {
    sp_bootstrap

    sp_discover_config || true

    if ! sp_load_config; then
        sp_log "state=config-load" "result=error" "severity=non-fatal"
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

    sp_idle_shell
}

main "$@"
