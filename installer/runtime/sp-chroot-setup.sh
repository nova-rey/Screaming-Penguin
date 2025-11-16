#!/bin/sh
# Screaming Penguin chroot setup (Phase 5).
# Configures hostname, locale, timezone, user, SSH, and GRUB inside the new system.

set -eu

# shellcheck disable=SC1091
. "$(dirname "$0")/lib/logging.sh"

sp_chroot_setup() {
    : "${SP_TARGET_MNT:=/mnt/target}"

    if [ ! -d "$SP_TARGET_MNT" ]; then
        log_error "Target mount point does not exist: $SP_TARGET_MNT"
        return 1
    fi

    if [ -z "${SP_CFG_HOSTNAME:-}" ] || [ -z "${SP_CFG_TIMEZONE:-}" ] || [ -z "${SP_CFG_LOCALE:-}" ]; then
        log_error "Configuration variables missing for chroot setup (hostname/locale/timezone)."
        return 1
    fi

    if [ -z "${SP_CFG_USER_NAME:-}" ]; then
        log_error "User name not set; cannot configure user."
        return 1
    fi

    log_info "Setting up chrooted system under '$SP_TARGET_MNT'…"

    # Mount virtual filesystems
    for d in dev proc sys run; do
        if [ -d "/$d" ]; then
            mkdir -p "$SP_TARGET_MNT/$d"
            mount --bind "/$d" "$SP_TARGET_MNT/$d"
        fi
    done

    chroot_cmd() {
        chroot "$SP_TARGET_MNT" /bin/sh -eu -c "$1"
    }

    # Hostname
    log_info "Configuring hostname: $SP_CFG_HOSTNAME"
    printf "%s\n" "$SP_CFG_HOSTNAME" >"$SP_TARGET_MNT/etc/hostname"

    # Timezone
    log_info "Configuring timezone: $SP_CFG_TIMEZONE"
    chroot_cmd "ln -sf '/usr/share/zoneinfo/$SP_CFG_TIMEZONE' /etc/localtime && echo '$SP_CFG_TIMEZONE' >/etc/timezone && (command -v dpkg-reconfigure >/dev/null 2>&1 && dpkg-reconfigure -f noninteractive tzdata || true)"

    # Locale
    log_info "Configuring locale: $SP_CFG_LOCALE"
    printf "%s UTF-8\n" "$SP_CFG_LOCALE" >"$SP_TARGET_MNT/etc/locale.gen"
    chroot_cmd "locale-gen && update-locale LANG=$SP_CFG_LOCALE"

    # User account
    log_info "Creating user: $SP_CFG_USER_NAME"
    chroot_cmd "id '$SP_CFG_USER_NAME' >/dev/null 2>&1 || useradd -m -s /bin/bash '$SP_CFG_USER_NAME'"

    if [ -n "${SP_CFG_USER_PASSWORD_HASH:-}" ] && [ "$SP_CFG_USER_PASSWORD_HASH" != "null" ]; then
        log_info "Setting password hash for user '$SP_CFG_USER_NAME'"
        chroot_cmd "usermod -p '$SP_CFG_USER_PASSWORD_HASH' '$SP_CFG_USER_NAME'"
    fi

    if [ "${SP_CFG_USER_SUDO:-false}" = "true" ]; then
        log_info "Adding user '$SP_CFG_USER_NAME' to sudo group"
        chroot_cmd "getent group sudo >/dev/null 2>&1 || groupadd sudo; usermod -aG sudo '$SP_CFG_USER_NAME'"
    fi

    # SSH
    if [ "${SP_CFG_SSH_ENABLE:-false}" = "true" ]; then
        log_info "Enabling SSH service and installing authorized_keys"
        chroot_cmd "systemctl enable ssh || true"

        ssh_dir="$SP_TARGET_MNT/home/$SP_CFG_USER_NAME/.ssh"
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"

        if command -v yq >/dev/null 2>&1 && [ -n "${SP_CFG_CONFIG_PATH:-}" ]; then
            log_info "Writing ssh.authorized_keys from config to authorized_keys"
            yq -r '.ssh.authorized_keys[]' "$SP_CFG_CONFIG_PATH" >"$ssh_dir/authorized_keys"
            chmod 600 "$ssh_dir/authorized_keys"
            chroot_cmd "chown -R '$SP_CFG_USER_NAME:$SP_CFG_USER_NAME' '/home/$SP_CFG_USER_NAME/.ssh'"
        else
            log_warn "yq or SP_CFG_CONFIG_PATH missing; cannot populate authorized_keys."
        fi
    else
        log_info "SSH disabled by configuration."
    fi

    # GRUB installation (BIOS + UEFI)
    log_info "Installing GRUB bootloader…"
    chroot_cmd "grub-install '$SP_TARGET_DISK_DEV' || true"
    chroot_cmd "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id='ScreamingPenguin' --recheck || true"
    chroot_cmd "update-grub || true"

    # Unmount virtual filesystems
    for d in run sys proc dev; do
        if mountpoint -q "$SP_TARGET_MNT/$d"; then
            umount "$SP_TARGET_MNT/$d"
        fi
    done

    log_info "Chroot setup complete."
    return 0
}
