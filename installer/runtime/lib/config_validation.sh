#!/bin/sh
# Screaming Penguin config validation (Phase 5).
# Loads and validates YAML configuration using yq.

set -eu

# shellcheck disable=SC1091
. "$(dirname "$0")/logging.sh"

sp_config_load() {
    config_path="$1"

    if [ ! -f "$config_path" ]; then
        log_error "Config file not found: $config_path"
        return 1
    fi

    if ! command -v yq >/dev/null 2>&1; then
        log_error "yq not found; cannot parse YAML config."
        return 1
    fi

    log_info "Loading installer config from '$config_path'"

    SP_CFG_TARGET_DISK="$(yq -r '.target.disk // ""' "$config_path")"
    SP_CFG_ROOTFS_PATH="$(yq -r '.rootfs.path // ""' "$config_path")"
    SP_CFG_HOSTNAME="$(yq -r '.system.hostname // ""' "$config_path")"
    SP_CFG_TIMEZONE="$(yq -r '.system.timezone // ""' "$config_path")"
    SP_CFG_LOCALE="$(yq -r '.system.locale // ""' "$config_path")"
    SP_CFG_USER_NAME="$(yq -r '.user.name // ""' "$config_path")"
    SP_CFG_USER_PASSWORD_HASH="$(yq -r '.user.password_hash // ""' "$config_path")"
    SP_CFG_USER_SUDO="$(yq -r '.user.sudo // "true"' "$config_path")"
    SP_CFG_SSH_ENABLE="$(yq -r '.ssh.enable // "false"' "$config_path")"
    SP_CFG_SSH_AUTHORIZED_KEYS_COUNT="$(yq -r '.ssh.authorized_keys | length // 0' "$config_path")"
    SP_CFG_REQUIRE_ERASE_WORD="$(yq -r '.safety.require_erase_word // "true"' "$config_path")"

    # Default rootfs path if omitted
    if [ -z "$SP_CFG_ROOTFS_PATH" ] || [ "$SP_CFG_ROOTFS_PATH" = "null" ]; then
        SP_CFG_ROOTFS_PATH="/config/rootfs/debian-rootfs.tar.gz"
    fi

    # Normalize booleans
    case "$SP_CFG_SSH_ENABLE" in
        true|True|yes|on|1) SP_CFG_SSH_ENABLE="true" ;;
        *) SP_CFG_SSH_ENABLE="false" ;;
    esac

    case "$SP_CFG_REQUIRE_ERASE_WORD" in
        true|True|yes|on|1) SP_CFG_REQUIRE_ERASE_WORD="true" ;;
        *) SP_CFG_REQUIRE_ERASE_WORD="false" ;;
    esac

    case "$SP_CFG_USER_SUDO" in
        true|True|yes|on|1) SP_CFG_USER_SUDO="true" ;;
        *) SP_CFG_USER_SUDO="false" ;;
    esac

    # Required fields
    if [ -z "$SP_CFG_TARGET_DISK" ] || [ "$SP_CFG_TARGET_DISK" = "null" ]; then
        log_error "Config missing required field: target.disk"
        return 1
    fi

    if [ -z "$SP_CFG_HOSTNAME" ] || [ "$SP_CFG_HOSTNAME" = "null" ]; then
        log_error "Config missing required field: system.hostname"
        return 1
    fi

    if [ -z "$SP_CFG_TIMEZONE" ] || [ "$SP_CFG_TIMEZONE" = "null" ]; then
        log_error "Config missing required field: system.timezone"
        return 1
    fi

    if [ -z "$SP_CFG_LOCALE" ] || [ "$SP_CFG_LOCALE" = "null" ]; then
        log_error "Config missing required field: system.locale"
        return 1
    fi

    if [ -z "$SP_CFG_USER_NAME" ] || [ "$SP_CFG_USER_NAME" = "null" ]; then
        log_error "Config missing required field: user.name"
        return 1
    fi

    # SSH/password safety
    if [ "$SP_CFG_SSH_ENABLE" = "false" ]; then
        if [ -z "$SP_CFG_USER_PASSWORD_HASH" ] || [ "$SP_CFG_USER_PASSWORD_HASH" = "null" ]; then
            log_error "Config invalid: SSH disabled but user.password_hash is missing."
            return 1
        fi
    else
        if [ "$SP_CFG_SSH_AUTHORIZED_KEYS_COUNT" -lt 1 ]; then
            log_error "Config invalid: SSH enabled but ssh.authorized_keys is empty."
            return 1
        fi
    fi

    export SP_CFG_CONFIG_PATH="$config_path"
    export SP_CFG_TARGET_DISK SP_CFG_ROOTFS_PATH
    export SP_CFG_HOSTNAME SP_CFG_TIMEZONE SP_CFG_LOCALE
    export SP_CFG_USER_NAME SP_CFG_USER_PASSWORD_HASH SP_CFG_USER_SUDO
    export SP_CFG_SSH_ENABLE SP_CFG_SSH_AUTHORIZED_KEYS_COUNT
    export SP_CFG_REQUIRE_ERASE_WORD

    log_info "Installer config loaded for target disk '$SP_CFG_TARGET_DISK'."
    return 0
}
