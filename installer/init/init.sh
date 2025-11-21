#!/bin/sh
# shellcheck shell=dash

# Minimal, POSIX-friendly bootstrap for the installer initramfs.

sp_log() {
    # Simple structured logger. All lines should start with [SP-INSTALLER].
    # Usage: sp_log "key=value" "message=..."
    printf '[SP-INSTALLER] %s\n' "$@" >/dev/console 2>&1
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
    CONFIG_CANDIDATES="/config/installer-config.yml /mnt/config/installer-config.yml"

    for p in $CONFIG_CANDIDATES; do
        if [ -f "$p" ]; then
            SP_CONFIG_PATH=$p
            export SP_CONFIG_PATH
            sp_log "state=discover-config" "config=found" "path=$p"
            return 0
        fi
    done

    sp_log "state=discover-config" "config=missing" "reason=not-found-in-default-paths"
    return 1
}

sp_idle_shell() {
    sp_log "state=idle-shell" "msg=waiting-for-next-stage"
    exec sh -i </dev/console >/dev/console 2>&1
}

main() {
    sp_bootstrap

    if sp_discover_config; then
        # Later stages will parse and act on this config.
        # For Stage 2 we only log success and stay idle.
        :
    fi

    sp_idle_shell
}

main "$@"
