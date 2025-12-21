#!/bin/sh
# shellcheck shell=sh

sp_bootstrap_usb_storage_collect_sys_block() {
    entries=""
    for entry in "$SP_SYS_BLOCK_ROOT"/*; do
        [ -e "$entry" ] || continue
        name="${entry##*/}"
        entries="${entries:+$entries }${name}"
    done

    if [ -z "$entries" ]; then
        printf '%s' "none"
        return 0
    fi

    printf '%s' "$entries"
    return 0
}

sp_bootstrap_usb_storage_collect_sd_devices() {
    entries=""
    for entry in "$SP_SYS_BLOCK_ROOT"/sd*; do
        [ -e "$entry" ] || continue
        name="${entry##*/}"
        case "$name" in
            sd*)
                entries="${entries:+$entries }${name}"
                ;;
        esac
    done

    if [ -z "$entries" ]; then
        printf '%s' "none"
        return 0
    fi

    printf '%s' "$entries"
    return 0
}

sp_bootstrap_usb_storage_wait_for_sd_devices() {
    attempts=0
    max_attempts=20
    while [ "$attempts" -lt "$max_attempts" ]; do
        devices="$(sp_bootstrap_usb_storage_collect_sd_devices)"
        if [ "$devices" != "none" ]; then
            printf '%s' "$devices"
            return 0
        fi
        attempts=$((attempts + 1))
        sleep 0.1
    done

    printf '%s' "$(sp_bootstrap_usb_storage_collect_sd_devices)"
    return 1
}

sp_bootstrap_usb_storage_run_test_trigger() {
    hook="${SP_TEST_USB_STORAGE_SCAN_TRIGGER:-}"
    if [ -z "$hook" ]; then
        return 0
    fi

    if [ -x "$hook" ]; then
        "$hook" "$SP_SYS_BLOCK_ROOT" "$SP_DEV_ROOT"
    else
        sh "$hook" "$SP_SYS_BLOCK_ROOT" "$SP_DEV_ROOT"
    fi
}

sp_bootstrap_usb_storage() {
    if [ -n "${SP_USB_STORAGE_SCAN_DONE:-}" ]; then
        return 0
    fi

    SP_USB_STORAGE_SCAN_DONE="1"
    export SP_USB_STORAGE_SCAN_DONE

    sys_before="$(sp_bootstrap_usb_storage_collect_sys_block)"
    sp_log "usb-storage-scan=begin" "sys-block-before=${sys_before:-none}"

    storage_modprobe="${SP_STORAGE_MODPROBE_BIN:-$(command -v modprobe 2>/dev/null || true)}"
    if [ -n "$storage_modprobe" ]; then
        for module in xhci_pci xhci_hcd ehci_pci ehci_hcd usb_storage uas scsi_mod sd_mod; do
            "$storage_modprobe" -q "$module" >/dev/null 2>&1 || true
        done
    else
        sp_log "state=storage-drivers" "phase=usb-storage-scan" "result=modprobe-unavailable"
    fi

    for host in /sys/class/scsi_host/host*; do
        [ -d "$host" ] || continue
        scan="${host}/scan"
        printf '%s\n' "- - -" > "$scan" 2>/dev/null || true
    done

    sp_bootstrap_usb_storage_run_test_trigger

    sd_devices="$(sp_bootstrap_usb_storage_wait_for_sd_devices)"
    sys_after="$(sp_bootstrap_usb_storage_collect_sys_block)"

    sp_log "usb-storage-scan=complete" \
        "devices=${sd_devices:-none}" \
        "sys-block-after=${sys_after:-none}"
}
