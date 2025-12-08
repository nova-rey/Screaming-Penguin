#!/bin/sh
# shellcheck shell=sh

sp_disk_execute_log() {
    log_device="${SP_LOG_DEVICE:-/dev/console}"
    printf '[SP-INSTALLER] %s\n' "$@" >>"$log_device" 2>&1
}

sp_disk_execute_marker() {
    sp_disk_execute_log "state=disk-exec" "marker=$1"
}

sp_disk_execute_error() {
    sp_disk_execute_log "state=disk-exec" "result=failed" "reason=$1"
}

sp_disk_execute_python_cmd() {
    if command -v sp_disk_layout_python_cmd >/dev/null 2>&1; then
        sp_disk_layout_python_cmd
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

sp_disk_execute_partition_dev() {
    disk_path="$1"
    index="$2"

    base=$(sp_dev_to_base "$disk_path")
    if [ -z "$base" ]; then
        return 1
    fi

    case "$base" in
        *[0-9])
            suffix="p$index"
            ;;
        *)
            suffix="$index"
            ;;
    esac

    printf '/dev/%s%s' "$base" "$suffix"
}

sp_disk_execute_parse_plan() {
    plan="${SP_DISK_LAYOUT_LAST_PLAN:-}"
    if [ -z "$plan" ]; then
        sp_disk_execute_error "plan-missing"
        return 1
    fi

    python_cmd=$(sp_disk_execute_python_cmd) || {
        sp_disk_execute_error "python-missing"
        return 1
    }

    python_script=$(cat <<'PY'
import json
import sys

def err(message: str) -> None:
    sys.stderr.write(message)
    sys.exit(1)

try:
    plan_data = json.load(sys.stdin)
except Exception as exc:  # pylint: disable=broad-except
    err(f"invalid-plan: {exc}\n")

target = sys.argv[1] if len(sys.argv) > 1 else None
if target not in (None, plan_data.get("target_disk")):
    err("target-mismatch: planner output does not match requested disk\n")

partitions = plan_data.get("partitions")
if not partitions:
    err("plan-invalid: no partitions defined\n")

for entry in partitions:
    try:
        index = int(entry.get("index", 0))
        role = entry.get("role", "").strip().lower()
        filesystem = entry.get("filesystem", "").strip().lower()
        start = int(entry.get("start_mib"))
        size = int(entry.get("size_mib"))
    except Exception as exc:  # pylint: disable=broad-except
        err(f"plan-invalid: {exc}\n")

    if index <= 0 or size <= 0:
        err("plan-invalid: invalid partition index or size\n")

    print(f"{index}|{role}|{filesystem}|{start}|{size}")
PY
    )

    parsed_output=$(
        printf '%s\n' "$plan" | "$python_cmd" -c "$python_script" "$SP_TARGET_DISK"
    )

    if [ -z "$parsed_output" ]; then
        sp_disk_execute_error "plan-empty"
        return 1
    fi

    SP_DISK_EXECUTE_PLAN_LINES="$parsed_output"
    export SP_DISK_EXECUTE_PLAN_LINES
    return 0
}

sp_disk_execute_require_write_gate() {
    if command -v sp_enforce_write_gate >/dev/null 2>&1; then
        if sp_enforce_write_gate; then
            return 0
        fi
        return 1
    fi

    sp_disk_execute_error "write-gate-hook-missing"
    return 1
}

sp_execute_partitioning() {
    if [ -z "${SP_DISK_EXECUTE_PLAN_LINES:-}" ]; then
        sp_disk_execute_error "plan-unavailable"
        return 1
    fi

    sp_disk_execute_log "state=disk-exec" "step=partitioning" "result=start" "disk=$SP_TARGET_DISK"

    if ! sgdisk -Z "$SP_TARGET_DISK" >/dev/null 2>&1; then
        sp_disk_execute_error "sgdisk-zap-failed"
        return 1
    fi

    if ! sgdisk -o "$SP_TARGET_DISK" >/dev/null 2>&1; then
        sp_disk_execute_error "sgdisk-init-failed"
        return 1
    fi

    partition_created=0
    while IFS='|' read -r index role filesystem start size; do
        if [ -z "$index" ] || [ -z "$role" ] || [ -z "$filesystem" ] || [ -z "$start" ] || [ -z "$size" ]; then
            sp_disk_execute_error "plan-entry-invalid"
            return 1
        fi

        target_part=$(sp_disk_execute_partition_dev "$SP_TARGET_DISK" "$index")
        if [ -z "$target_part" ]; then
            sp_disk_execute_error "partition-dev-lookup-failed"
            return 1
        fi

        case "$role" in
            efi)
                type_code=EF00
                part_key="EFI"
                ;;
            root)
                type_code=8300
                part_key="ROOT"
                ;;
            *)
                type_code=8300
                part_key="ROOT"
                ;;
        esac

        if ! sgdisk -n "${index}:${start}M:+${size}M" -t "${index}:${type_code}" "$SP_TARGET_DISK" >/dev/null 2>&1; then
            sp_disk_execute_error "sgdisk-create-failed"
            return 1
        fi

        case "$part_key" in
            EFI)
                SP_DISK_EXECUTE_EFI_PART="$target_part"
                ;;
            ROOT)
                SP_DISK_EXECUTE_ROOT_PART="$target_part"
                ;;
        esac

        partition_created=$((partition_created + 1))
    done <<EOF
$SP_DISK_EXECUTE_PLAN_LINES
EOF

    if [ "$partition_created" -eq 0 ]; then
        sp_disk_execute_error "partitioning-empty"
        return 1
    fi

    if command -v partprobe >/dev/null 2>&1; then
        if ! partprobe "$SP_TARGET_DISK" >/dev/null 2>&1; then
            sp_disk_execute_log "state=disk-exec" "step=partition-table" "note=partprobe-failed"
        fi
    fi

    if ! partition_dump=$(sfdisk -l "$SP_TARGET_DISK" 2>&1); then
        sp_disk_execute_error "sfdisk-list-failed"
        return 1
    fi

    printf '%s\n' "$partition_dump" | while IFS= read -r line; do
        sp_disk_execute_log "state=disk-exec" "step=partition-table" "line=$line"
    done

    sp_disk_execute_log "state=disk-exec" "step=partitioning" "result=ok" "partitions=$partition_created"
    return 0
}

sp_execute_mkfs_efi() {
    part="${SP_DISK_EXECUTE_EFI_PART:-}"
    if [ -z "$part" ]; then
        sp_disk_execute_error "efi-part-missing"
        return 1
    fi

    if ! command -v mkfs.vfat >/dev/null 2>&1; then
        sp_disk_execute_error "mkfs-vfat-missing"
        return 1
    fi

    if ! mkfs.vfat -F 32 -n SP_EFI "$part" >/dev/null 2>&1; then
        sp_disk_execute_error "mkfs-vfat-failed"
        return 1
    fi

    sp_disk_execute_log "state=disk-exec" "step=mkfs-efi" "result=ok" "partition=$part"
    return 0
}

sp_execute_mkfs_root() {
    part="${SP_DISK_EXECUTE_ROOT_PART:-}"
    if [ -z "$part" ]; then
        sp_disk_execute_error "root-part-missing"
        return 1
    fi

    if ! command -v mkfs.ext4 >/dev/null 2>&1; then
        sp_disk_execute_error "mkfs-ext4-missing"
        return 1
    fi

    if ! mkfs.ext4 -F -L rootfs "$part" >/dev/null 2>&1; then
        sp_disk_execute_error "mkfs-ext4-failed"
        return 1
    fi

    sp_disk_execute_log "state=disk-exec" "step=mkfs-root" "result=ok" "partition=$part"
    return 0
}

sp_execute_gpt_plan() {
    if [ -z "${SP_TARGET_DISK:-}" ]; then
        sp_disk_execute_error "missing-target"
        return 1
    fi

    sp_disk_execute_marker "START"

    if ! sp_disk_execute_require_write_gate; then
        sp_disk_execute_marker "END"
        return 1
    fi

    if ! sp_plan_gpt_layout "$SP_TARGET_DISK"; then
        sp_disk_execute_error "planner-failed"
        sp_disk_execute_marker "END"
        return 1
    fi

    if ! sp_disk_execute_parse_plan; then
        sp_disk_execute_marker "END"
        return 1
    fi

    if ! sp_execute_partitioning; then
        sp_disk_execute_marker "END"
        return 1
    fi

    if ! sp_execute_mkfs_efi; then
        sp_disk_execute_marker "END"
        return 1
    fi

    if ! sp_execute_mkfs_root; then
        sp_disk_execute_marker "END"
        return 1
    fi

    sp_disk_execute_log "state=disk-exec" "result=ok" "disk=$SP_TARGET_DISK"
    sp_disk_execute_marker "END"
    return 0
}
