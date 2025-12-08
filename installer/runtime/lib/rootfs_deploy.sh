#!/bin/sh
# shellcheck shell=sh

SP_ROOTFS_DEFAULT_TARBALL="/config/os/rootfs.tar.gz"
SP_ROOTFS_DEFAULT_TARGET_MOUNT="/mnt/target"

if ! command -v sp_log >/dev/null 2>&1; then
    SP_LOG_DEVICE="${SP_LOG_DEVICE:-/dev/console}"
    sp_log() {
        printf '[SP-INSTALLER] %s\n' "$@" >>"$SP_LOG_DEVICE" 2>&1
    }
fi

sp_rootfs_marker() {
    marker="$1"
    shift
    sp_log "state=rootfs" "marker=$marker" "$@"
}

sp_rootfs_debug_marker() {
    if [ "${SP_DEBUG_ROOTFS:-0}" = "1" ]; then
        sp_rootfs_marker "$@"
    fi
}

sp_rootfs_log_step() {
    step="$1"
    shift
    sp_log "state=rootfs" "step=$step" "$@"
}

sp_rootfs_python_cmd() {
    if [ -n "${SP_ROOTFS_PYTHON_CMD:-}" ]; then
        printf '%s' "$SP_ROOTFS_PYTHON_CMD"
        return 0
    fi

    if command -v python3 >/dev/null 2>&1; then
        printf '%s' "python3"
        return 0
    fi

    if command -v python >/dev/null 2>&1; then
        printf '%s' "python"
        return 0
    fi

    return 1
}

sp_rootfs_yq_cmd() {
    if [ -n "${SP_ROOTFS_YQ_CMD:-}" ]; then
        printf '%s' "$SP_ROOTFS_YQ_CMD"
        return 0
    fi

    if command -v yq >/dev/null 2>&1; then
        SP_ROOTFS_YQ_CMD="$(command -v yq)"
        printf '%s' "$SP_ROOTFS_YQ_CMD"
        return 0
    fi

    return 1
}

sp_rootfs_yq_value() {
    expr="$1"
    if ! cmd=$(sp_rootfs_yq_cmd); then
        return 1
    fi

    raw=$($cmd -r "$expr" "$SP_CONFIG_PATH" 2>/dev/null || echo "")
    trimmed=$(sp_trim "$raw")
    if [ "$trimmed" = "null" ]; then
        trimmed=""
    fi
    printf '%s' "$trimmed"
}

sp_rootfs_collect_ssh_keys() {
    expr='(.installer.rootfs.ssh_authorized_keys // .ssh.authorized_keys // [])[]'
    if ! cmd=$(sp_rootfs_yq_cmd); then
        return 1
    fi

    raw=$($cmd -r "$expr" "$SP_CONFIG_PATH" 2>/dev/null || true)
    filtered=$(printf '%s\n' "$raw" | awk 'NF')
    SP_ROOTFS_SSH_KEYS="$filtered"
}

sp_rootfs_determine_target_dir() {
    # Allow tests or overrides to reuse an existing directory instead of mounting.
    if [ -n "${SP_ROOTFS_TARGET_DIR_OVERRIDE:-}" ]; then
        SP_ROOTFS_TARGET_DIR="$SP_ROOTFS_TARGET_DIR_OVERRIDE"
        SP_ROOTFS_TARGET_OVERRIDE_ACTIVE=1
    else
        SP_ROOTFS_TARGET_DIR="${SP_ROOTFS_TARGET_MOUNT:-$SP_ROOTFS_DEFAULT_TARGET_MOUNT}"
        SP_ROOTFS_TARGET_OVERRIDE_ACTIVE=0
    fi
}

sp_rootfs_resolve_config() {
    if [ -z "${SP_CONFIG_PATH:-}" ] || [ ! -r "$SP_CONFIG_PATH" ]; then
        sp_rootfs_log_step "config" "result=failed" "reason=config-missing" "path=${SP_CONFIG_PATH:-unset}"
        return 1
    fi

    if ! sp_rootfs_yq_cmd >/dev/null 2>&1; then
        sp_rootfs_log_step "config" "result=failed" "reason=yq-missing"
        return 1
    fi

    tarball=$(sp_rootfs_yq_value '.installer.rootfs.tarball // ""')
    if [ -z "$tarball" ]; then
        tarball="$SP_ROOTFS_DEFAULT_TARBALL"
    fi

    target_mount=$(sp_rootfs_yq_value '.installer.rootfs.target_mount // ""')
    if [ -z "$target_mount" ]; then
        target_mount="$SP_ROOTFS_DEFAULT_TARGET_MOUNT"
    fi

    hostname=$(sp_rootfs_yq_value '.installer.rootfs.hostname // .system.hostname // ""')
    timezone=$(sp_rootfs_yq_value '.installer.rootfs.timezone // .system.timezone // ""')
    locale=$(sp_rootfs_yq_value '.installer.rootfs.locale // .system.locale // ""')
    username=$(sp_rootfs_yq_value '.installer.rootfs.username // .user.name // ""')
    password_hash=$(sp_rootfs_yq_value '.installer.rootfs.password_hash // .user.password_hash // ""')

    sp_rootfs_collect_ssh_keys || true

    SP_ROOTFS_TARBALL="$tarball"
    SP_ROOTFS_TARGET_MOUNT="$target_mount"
    SP_ROOTFS_HOSTNAME="$hostname"
    SP_ROOTFS_TIMEZONE="$timezone"
    SP_ROOTFS_LOCALE="$locale"
    SP_ROOTFS_USERNAME="$username"
    SP_ROOTFS_PASSWORD_HASH="$password_hash"

    sp_rootfs_determine_target_dir

    if [ -z "${SP_ROOTFS_TARGET_DIR:-}" ]; then
        sp_rootfs_log_step "config" "result=failed" "reason=target-dir-missing"
        return 1
    fi

    if [ -z "$SP_ROOTFS_HOSTNAME" ]; then
        sp_rootfs_log_step "config" "result=failed" "reason=hostname-missing"
        return 1
    fi

    if [ -z "$SP_ROOTFS_TIMEZONE" ]; then
        sp_rootfs_log_step "config" "result=failed" "reason=timezone-missing"
        return 1
    fi

    if [ -z "$SP_ROOTFS_LOCALE" ]; then
        sp_rootfs_log_step "config" "result=failed" "reason=locale-missing"
        return 1
    fi

    if [ -z "$SP_ROOTFS_USERNAME" ]; then
        sp_rootfs_log_step "config" "result=failed" "reason=username-missing"
        return 1
    fi

    sp_rootfs_log_step "config" "result=ok" "tarball=$SP_ROOTFS_TARBALL" "target=$SP_ROOTFS_TARGET_DIR"
    sp_rootfs_debug_marker "config" "hostname=$SP_ROOTFS_HOSTNAME" "timezone=$SP_ROOTFS_TIMEZONE" "locale=$SP_ROOTFS_LOCALE"
    return 0
}

sp_rootfs_mount_target() {
    target_dir="${SP_ROOTFS_TARGET_DIR:-}"
    if [ -z "$target_dir" ]; then
        sp_rootfs_log_step "target" "result=failed" "reason=target-path-missing"
        return 1
    fi

    if [ "${SP_ROOTFS_TARGET_OVERRIDE_ACTIVE:-0}" = "1" ]; then
        sp_rootfs_log_step "target" "result=override" "path=$target_dir"
        sp_rootfs_debug_marker "target" "reason=override"
        return 0
    fi

    if [ -z "${SP_DISK_EXECUTE_ROOT_PART:-}" ]; then
        sp_rootfs_log_step "target" "result=failed" "reason=root-part-missing"
        return 1
    fi

    mkdir -p "$target_dir"

    sp_rootfs_debug_marker "target" "partition=$SP_DISK_EXECUTE_ROOT_PART"
    if ! mount "$SP_DISK_EXECUTE_ROOT_PART" "$target_dir" >/dev/null 2>&1; then
        sp_rootfs_log_step "target" "result=failed" "reason=mount-failed" "partition=$SP_DISK_EXECUTE_ROOT_PART" "path=$target_dir"
        return 1
    fi

    SP_ROOTFS_TARGET_MOUNTED=1
    sp_rootfs_log_step "target" "result=ok" "partition=$SP_DISK_EXECUTE_ROOT_PART" "path=$target_dir"
    return 0
}

sp_rootfs_extract_tarball() {
    target_dir="${SP_ROOTFS_TARGET_DIR:-}"
    tarball="${SP_ROOTFS_TARBALL:-}"

    if [ -z "$target_dir" ] || [ -z "$tarball" ]; then
        sp_rootfs_log_step "extract" "result=failed" "reason=params-missing"
        return 1
    fi

    if [ ! -f "$tarball" ]; then
        sp_rootfs_log_step "extract" "result=failed" "reason=tarball-missing" "path=$tarball"
        return 1
    fi

    if ! command -v tar >/dev/null 2>&1; then
        sp_rootfs_log_step "extract" "result=failed" "reason=tar-missing"
        return 1
    fi

    sp_rootfs_debug_marker "extract" "target=$target_dir" "tarball=$tarball"

    mkdir -p "$target_dir"
    if ! tar -C "$target_dir" -xpf "$tarball" --numeric-owner >/dev/null 2>&1; then
        sp_rootfs_log_step "extract" "result=failed" "reason=tar-extract-failed"
        return 1
    fi

    sp_rootfs_log_step "extract" "result=ok" "path=$target_dir"
    return 0
}

sp_rootfs_bind_virtuals() {
    if [ "${SP_ROOTFS_TARGET_OVERRIDE_ACTIVE:-0}" = "1" ]; then
        sp_rootfs_log_step "bind" "result=skipped" "reason=target-override"
        return 0
    fi

    target_dir="${SP_ROOTFS_TARGET_DIR:-}"
    if [ -z "$target_dir" ]; then
        sp_rootfs_log_step "bind" "result=failed" "reason=target-missing"
        return 1
    fi

    for entry in run sys proc dev/pts dev; do
        dest="$target_dir/$entry"
        mkdir -p "$dest"
        if ! mount --bind "/$entry" "$dest" >/dev/null 2>&1; then
            sp_rootfs_log_step "bind" "result=failed" "target=$dest" "source=/$entry"
            return 1
        fi
    done

    SP_ROOTFS_VFS_BOUND=1
    sp_rootfs_log_step "bind" "result=ok"
    return 0
}

sp_rootfs_chroot_exec() {
    if ! command -v chroot >/dev/null 2>&1; then
        sp_rootfs_log_step "chroot" "result=failed" "reason=chroot-missing"
        return 1
    fi

    chroot "$SP_ROOTFS_TARGET_DIR" "$@"
}

sp_rootfs_write_hostname() {
    target_dir="${SP_ROOTFS_TARGET_DIR:-}"
    mkdir -p "$target_dir/etc"
    printf '%s\n' "$SP_ROOTFS_HOSTNAME" >"$target_dir/etc/hostname"

    cat <<EOF >"$target_dir/etc/hosts"
127.0.0.1 localhost
127.0.1.1 $SP_ROOTFS_HOSTNAME
::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

    sp_rootfs_log_step "chroot-hostname" "result=ok" "hostname=$SP_ROOTFS_HOSTNAME"
}

sp_rootfs_configure_timezone() {
    target_dir="${SP_ROOTFS_TARGET_DIR:-}"
    zonefile="$target_dir/usr/share/zoneinfo/$SP_ROOTFS_TIMEZONE"

    if [ ! -f "$zonefile" ]; then
        sp_rootfs_log_step "chroot-timezone" "result=failed" "reason=zone-missing" "timezone=$SP_ROOTFS_TIMEZONE"
        return 1
    fi

    mkdir -p "$target_dir/etc"
    [ -e "$target_dir/etc/localtime" ] && rm -f "$target_dir/etc/localtime"
    ln -sf "$zonefile" "$target_dir/etc/localtime"
    printf '%s\n' "$SP_ROOTFS_TIMEZONE" >"$target_dir/etc/timezone"
    sp_rootfs_log_step "chroot-timezone" "result=ok" "timezone=$SP_ROOTFS_TIMEZONE"
    return 0
}

sp_rootfs_ensure_locale_entry() {
    locale_file="$SP_ROOTFS_TARGET_DIR/etc/locale.gen"
    if [ ! -f "$locale_file" ]; then
        sp_rootfs_log_step "chroot-locale" "result=warn" "reason=locale-gen-missing"
        return 0
    fi

    if cmd=$(sp_rootfs_python_cmd); then
        "$cmd" - "$SP_ROOTFS_LOCALE" "$locale_file" <<'PY'
import pathlib
import sys

entry = sys.argv[1].strip()
path = pathlib.Path(sys.argv[2])
lines = path.read_text().splitlines()
normalized = entry
found = False
result = []
for line in lines:
    stripped = line.strip()
    match = stripped.lstrip('#').strip()
    if match == normalized:
        result.append(normalized)
        found = True
    else:
        result.append(line)
if not found:
    result.append(normalized)
path.write_text("\n".join(result) + "\n")
PY
        return 0
    fi

    sp_rootfs_log_step "chroot-locale" "result=warn" "reason=python-missing"
    if ! grep -Fqx "$SP_ROOTFS_LOCALE" "$locale_file" 2>/dev/null; then
        printf '%s\n' "$SP_ROOTFS_LOCALE" >>"$locale_file"
    fi
    return 0
}

sp_rootfs_configure_locale() {
    if [ -z "$SP_ROOTFS_LOCALE" ]; then
        sp_rootfs_log_step "chroot-locale" "result=failed" "reason=locale-missing"
        return 1
    fi

    sp_rootfs_ensure_locale_entry || return 1

    if ! sp_rootfs_chroot_exec locale-gen >/dev/null 2>&1; then
        sp_rootfs_log_step "chroot-locale" "result=failed" "reason=locale-gen-failed"
        return 1
    fi

    sp_rootfs_log_step "chroot-locale" "result=ok" "locale=$SP_ROOTFS_LOCALE"
    return 0
}

sp_rootfs_create_primary_user() {
    if [ -z "$SP_ROOTFS_USERNAME" ]; then
        sp_rootfs_log_step "chroot-user" "result=failed" "reason=username-missing"
        return 1
    fi

    user_home="/home/$SP_ROOTFS_USERNAME"

    if [ -n "$SP_ROOTFS_PASSWORD_HASH" ]; then
        if ! sp_rootfs_chroot_exec useradd --create-home --shell /bin/bash --user-group --home-dir "$user_home" --password "$SP_ROOTFS_PASSWORD_HASH" "$SP_ROOTFS_USERNAME"; then
            sp_rootfs_log_step "chroot-user" "result=failed" "reason=useradd-failed"
            return 1
        fi
    else
        if ! sp_rootfs_chroot_exec useradd --create-home --shell /bin/bash --user-group --home-dir "$user_home" "$SP_ROOTFS_USERNAME"; then
            sp_rootfs_log_step "chroot-user" "result=failed" "reason=useradd-failed"
            return 1
        fi
        if ! sp_rootfs_chroot_exec passwd -l "$SP_ROOTFS_USERNAME" >/dev/null 2>&1; then
            sp_rootfs_log_step "chroot-user" "result=failed" "reason=passwd-lock-failed"
            return 1
        fi
    fi

    sp_rootfs_log_step "chroot-user" "result=ok" "user=$SP_ROOTFS_USERNAME"
    return 0
}

sp_rootfs_seed_ssh_keys() {
    if [ -z "${SP_ROOTFS_SSH_KEYS:-}" ]; then
        sp_rootfs_log_step "chroot-ssh" "result=skip" "reason=no-keys"
        return 0
    fi

    host_home="$SP_ROOTFS_TARGET_DIR/home/$SP_ROOTFS_USERNAME"
    ssh_dir="$host_home/.ssh"
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    printf '%s\n' "$SP_ROOTFS_SSH_KEYS" >"$ssh_dir/authorized_keys"
    chmod 600 "$ssh_dir/authorized_keys"

    if ! sp_rootfs_chroot_exec chown -R "$SP_ROOTFS_USERNAME:$SP_ROOTFS_USERNAME" "/home/$SP_ROOTFS_USERNAME/.ssh" >/dev/null 2>&1; then
        sp_rootfs_log_step "chroot-ssh" "result=failed" "reason=chown-failed"
        return 1
    fi

    sp_rootfs_log_step "chroot-ssh" "result=ok" "user=$SP_ROOTFS_USERNAME"
    return 0
}

sp_rootfs_configure_chroot() {
    target_dir="${SP_ROOTFS_TARGET_DIR:-}"
    if [ -z "$target_dir" ]; then
        sp_rootfs_log_step "chroot" "result=failed" "reason=target-missing"
        return 1
    fi

    sp_rootfs_debug_marker "chroot" "target=$target_dir"

    sp_rootfs_write_hostname
    sp_rootfs_configure_timezone || return 1
    sp_rootfs_configure_locale || return 1
    sp_rootfs_create_primary_user || return 1
    sp_rootfs_seed_ssh_keys || return 1

    return 0
}

sp_rootfs_unmount_virtuals() {
    if [ "${SP_ROOTFS_VFS_BOUND:-0}" != "1" ]; then
        return 0
    fi

    target_dir="${SP_ROOTFS_TARGET_DIR:-}"
    if [ -z "$target_dir" ]; then
        return 0
    fi

    for entry in dev dev/pts proc sys run; do
        mount_point="$target_dir/$entry"
        umount "$mount_point" >/dev/null 2>&1 || sp_rootfs_log_step "unbind" "result=warn" "path=$mount_point"
    done

    SP_ROOTFS_VFS_BOUND=0
}

sp_rootfs_unmount_target() {
    if [ "${SP_ROOTFS_TARGET_MOUNTED:-0}" != "1" ]; then
        return 0
    fi

    target_dir="${SP_ROOTFS_TARGET_DIR:-}"
    if [ -z "$target_dir" ]; then
        return 0
    fi

    umount "$target_dir" >/dev/null 2>&1 || sp_rootfs_log_step "unbind" "result=warn" "path=$target_dir"
    SP_ROOTFS_TARGET_MOUNTED=0
}

sp_rootfs_deploy_and_configure() {
    sp_rootfs_marker "START"

    if [ "${SP_SKIP_ROOTFS_DEPLOY:-0}" = "1" ]; then
        sp_rootfs_log_step "deploy" "result=skipped" "reason=skip-rootfs-deploy"
        sp_rootfs_marker "END"
        return 0
    fi

    if ! sp_rootfs_resolve_config; then
        sp_rootfs_marker "END" "result=failed"
        return 1
    fi

    result=1
    if sp_rootfs_mount_target && sp_rootfs_extract_tarball && sp_rootfs_bind_virtuals; then
        if [ "${SP_SKIP_CHROOT_CONFIG:-0}" = "1" ]; then
            sp_rootfs_log_step "chroot" "result=skipped" "reason=skip-chroot-config"
            result=0
        else
            if sp_rootfs_configure_chroot; then
                result=0
            fi
        fi
    fi

    sp_rootfs_unmount_virtuals
    sp_rootfs_unmount_target

    if [ "$result" -eq 0 ]; then
        sp_rootfs_marker "END" "result=ok"
    else
        sp_rootfs_marker "END" "result=failed"
    fi

    return "$result"
}
