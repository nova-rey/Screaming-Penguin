#!/bin/sh
# Screaming Penguin initramfs config helpers (stub phase)

# Expected mountpoint for the config partition (to be mounted in a later phase).
SP_CONFIG_MOUNT="/config"
SP_CONFIG_YAML="${SP_CONFIG_MOUNT}/installer-config.yml"
SP_CONFIG_STAGING_DIR="/run/sp/config"
SP_CONFIG_STAGING_YAML="${SP_CONFIG_STAGING_DIR}/installer-config.yml"

# Probe for a pre-mounted config partition and log what we find.
# This is intentionally non-fatal in P1-C: missing config should not break CI.
sp_config_probe() {
    if ! command -v sp_log_info >/dev/null 2>&1; then
        # Logging not available; fail silently.
        return 0
    fi

    sp_log_info "[SP-CONFIG]" "Probing for installer config at ${SP_CONFIG_YAML}"

    if [ ! -d "${SP_CONFIG_MOUNT}" ]; then
        sp_log_warn "[SP-CONFIG]" "Config mountpoint ${SP_CONFIG_MOUNT} not present (stub, non-fatal)"
        return 0
    fi

    if [ ! -f "${SP_CONFIG_YAML}" ]; then
        sp_log_warn "[SP-CONFIG]" "No installer-config.yml found at ${SP_CONFIG_YAML} (stub, non-fatal)"
        return 0
    fi

    # Best-effort staging into /run for later phases.
    mkdir -p "${SP_CONFIG_STAGING_DIR}" 2>/dev/null || true
    cp "${SP_CONFIG_YAML}" "${SP_CONFIG_STAGING_YAML}" 2>/dev/null || true

    sp_log_info "[SP-CONFIG]" "Found installer-config.yml and staged copy to ${SP_CONFIG_STAGING_YAML} (stub)"
    return 0
}
