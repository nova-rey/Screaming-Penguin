#!/bin/sh
#
# sanity_checks.sh
#
# Environment and safety checks before attempting any disk operations.
#

set -eu

err() {
    echo "[ouroboros][sanity] ERROR: $*" >&2
    exit 1
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        err "must run as root"
    fi
}

check_tools() {
    required_tools="dd lsblk sgdisk sync"
    for t in $required_tools; do
        if ! command -v "$t" >/dev/null 2>&1; then
            err "required tool '$t' is missing"
        fi
    done
}

check_ram_context() {
    # Best-effort check: verify rootfs is a tmpfs or overlay on tmpfs in future.
    # For now we simply log the filesystem type for informational purposes.
    root_type=$(awk '$2=="/" {print $3}' /proc/mounts || echo "unknown")
    echo "[ouroboros][sanity] root filesystem type: ${root_type}"
}

main() {
    check_root
    check_tools
    check_ram_context
    echo "[ouroboros][sanity] all basic checks passed"
}

main "$@"
