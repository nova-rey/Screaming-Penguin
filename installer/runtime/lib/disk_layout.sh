#!/bin/sh
# shellcheck shell=sh

sp_disk_layout_trim() {
    printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

sp_disk_layout_strip_quotes() {
    value="$1"

    # Remove surrounding double quotes
    while [ "${value#\"}" != "$value" ]; do
        value=${value#\"}
    done
    while [ "${value%\"}" != "$value" ]; do
        value=${value%\"}
    done

    # Remove surrounding single quotes
    while [ "${value#\'}" != "$value" ]; do
        value=${value#\'}
    done
    while [ "${value%\'}" != "$value" ]; do
        value=${value%\'}
    done

    # Normalize null-like values to empty
    case "$value" in
        null|NULL|Null)
            printf ''
            return 0
            ;;
    esac

    printf '%s' "$value"
}

sp_disk_layout_python_cmd() {
    if [ -n "${SP_DISK_LAYOUT_PYTHON:-}" ]; then
        printf '%s' "$SP_DISK_LAYOUT_PYTHON"
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

sp_disk_layout_yaml_value() {
    config_path="$1"
    key_path="$2"

    if [ -z "$config_path" ] || [ ! -r "$config_path" ]; then
        return 1
    fi

    python_cmd=$(sp_disk_layout_python_cmd) || return 1

    "$python_cmd" - "$config_path" "$key_path" <<'PY'
import sys
from pathlib import Path

def clean_value(value):
    value = value.strip()
    while len(value) >= 2 and (
        (value[0] == '"' and value[-1] == '"')
        or (value[0] == "'" and value[-1] == "'")
    ):
        value = value[1:-1].strip()
    if value.lower() == "null":
        return ""
    return value

config = Path(sys.argv[1])
keys = sys.argv[2].split(".")
lines = config.read_text().splitlines()
stack = []
indents = []

for line in lines:
    fragment = line.split("#", 1)[0]
    if not fragment.strip():
        continue

    indent = len(fragment) - len(fragment.lstrip(" \t"))
    trimmed = fragment.strip()

    if ":" not in trimmed:
        continue

    key, _, raw_value = trimmed.partition(":")
    key = key.strip()
    value = raw_value.strip()

    while indents and indent <= indents[-1]:
        stack.pop()
        indents.pop()

    stack.append(key)
    indents.append(indent)

    if len(stack) == len(keys) and stack == keys:
        print(clean_value(value))
        sys.exit(0)

sys.exit(1)
PY
}

sp_disk_layout_to_int() {
    value=$(sp_disk_layout_trim "$1")
    default_value="$2"

    if [ -z "$value" ]; then
        printf '%s' "$default_value"
        return 0
    fi

    if ! printf '%s' "$value" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then
        printf '%s' "$default_value"
        return 0
    fi

    printf '%s' "$(printf '%s' "$value" | awk '{printf "%d", $0}')"
}

sp_disk_layout_dev_to_base() {
    path="$1"
    path=${path#/dev/}
    printf '%s' "$path"
}

sp_disk_layout_align_up() {
    value="$1"
    align="$2"

    if [ -z "$align" ] || [ "$align" -le 0 ]; then
        align=1
    fi

    q=$(( (value + align - 1) / align ))
    printf '%s' "$(( q * align ))"
}

sp_disk_layout_disk_size_bytes() {
    if [ -n "${SP_DISK_LAYOUT_TEST_DISK_SIZE_BYTES:-}" ]; then
        printf '%s' "$SP_DISK_LAYOUT_TEST_DISK_SIZE_BYTES"
        return 0
    fi

    disk="$1"
    base=$(sp_disk_layout_dev_to_base "$disk")

    if [ -n "${SP_DISK_LAYOUT_SIZE_OVERRIDE_PATH:-}" ]; then
        size_file="$SP_DISK_LAYOUT_SIZE_OVERRIDE_PATH"
    else
        size_file="/sys/block/$base/size"
    fi

    if [ ! -r "$size_file" ]; then
        return 1
    fi

    sectors=$(cat "$size_file" 2>/dev/null)
    if [ -z "$sectors" ]; then
        return 1
    fi

    printf '%s' "$(awk -v s="$sectors" 'BEGIN { printf "%d", s * 512 }')"
}

sp_disk_layout_require_block_device() {
    disk="$1"

    if [ "${SP_DISK_LAYOUT_ASSUME_TARGET_BLOCK:-0}" = "1" ]; then
        return 0
    fi

    if [ -b "$disk" ]; then
        return 0
    fi

    base=$(sp_disk_layout_dev_to_base "$disk")
    if [ -b "/dev/$base" ]; then
        return 0
    fi

    return 1
}

sp_select_target_disk() {
    provided="$1"
    target="$provided"

    if [ -z "$target" ]; then
        target="${SP_TARGET_DISK:-}"
    fi
    if [ -z "$target" ]; then
        target="${SP_CFG_TARGET_DISK:-}"
    fi
    if [ -z "$target" ] && [ -n "${SP_CONFIG_PATH:-}" ]; then
        if disk_value=$(sp_disk_layout_yaml_value "$SP_CONFIG_PATH" "target.disk"); then
            target=$(sp_disk_layout_strip_quotes "$disk_value")
        fi
    fi

    if [ -z "$target" ]; then
        sp_disk_layout_error "target disk not configured"
        return 1
    fi

    case "$target" in
        /dev/*)
            ;; # already prefixed
        *)
            target="/dev/$target"
            ;;
    esac

    if ! sp_disk_layout_require_block_device "$target"; then
        sp_disk_layout_error "target disk '$target' is not a block device"
        return 1
    fi

    printf '%s' "$target"
}

sp_disk_layout_error() {
    message="$1"
    printf '[SP-INSTALLER] disk-layout error: %s\n' "$message" >&2
}

sp_plan_partition_entries() {
    target_disk="$1"
    total_bytes="$2"
    efi_size_mib="$3"
    efi_alignment_mib="$4"
    root_alignment_mib="$5"
    root_reserved_mib="$6"

    total_mib=$(awk -v bytes="$total_bytes" 'BEGIN { printf "%d", bytes / 1024 / 1024 }')

    if [ "$efi_alignment_mib" -le 0 ]; then
        efi_alignment_mib=1
    fi
    if [ "$root_alignment_mib" -le 0 ]; then
        root_alignment_mib=1
    fi

    efi_start_mib=$(sp_disk_layout_align_up 1 "$efi_alignment_mib")
    root_start_candidate=$(( efi_start_mib + efi_size_mib ))
    root_start_mib=$(sp_disk_layout_align_up "$root_start_candidate" "$root_alignment_mib")

    guard_mib="$root_reserved_mib"
    if [ "$guard_mib" -lt 0 ]; then
        guard_mib=0
    fi

    available_mib=$(( total_mib - root_start_mib - guard_mib ))
    if [ "$available_mib" -le 0 ]; then
        sp_disk_layout_error "disk '$target_disk' (${total_mib}MiB) is too small for the requested layout"
        return 1
    fi

    printf '{\n'
    printf '  "target_disk": "%s",\n' "$target_disk"
    printf '  "table": "gpt",\n'
    printf '  "partitions": [\n'
    printf '    {\n'
    printf '      "index": 1,\n'
    printf '      "role": "efi",\n'
    printf '      "type": "EFI System",\n'
    printf '      "start_mib": %s,\n' "$efi_start_mib"
    printf '      "size_mib": %s,\n' "$efi_size_mib"
    printf '      "filesystem": "fat32"\n'
    printf '    },\n'
    printf '    {\n'
    printf '      "index": 2,\n'
    printf '      "role": "root",\n'
    printf '      "type": "Linux filesystem",\n'
    printf '      "start_mib": %s,\n' "$root_start_mib"
    printf '      "size_mib": %s,\n' "$available_mib"
    printf '      "filesystem": "ext4"\n'
    printf '    }\n'
    printf '  ]\n'
    printf '}\n'
}

sp_plan_gpt_layout() {
    target_disk="$1"

    if [ -z "$target_disk" ] && [ -n "${SP_TARGET_DISK:-}" ]; then
        target_disk="$SP_TARGET_DISK"
    fi

    if [ -z "$target_disk" ]; then
        sp_disk_layout_error "target disk must be provided to the planner"
        return 1
    fi

    disk_bytes=""
    if ! disk_bytes=$(sp_disk_layout_disk_size_bytes "$target_disk"); then
        sp_disk_layout_error "could not read size for disk '$target_disk'"
        return 1
    fi

    efi_size_override="${SP_DISK_LAYOUT_EFI_SIZE_MIB:-}"
    efi_alignment_override="${SP_DISK_LAYOUT_EFI_ALIGNMENT_MIB:-}"
    root_alignment_override="${SP_DISK_LAYOUT_ROOT_ALIGNMENT_MIB:-}"
    root_reserved_override="${SP_DISK_LAYOUT_ROOT_RESERVED_MIB:-}"

    if [ -z "$efi_size_override" ] && [ -n "${SP_CONFIG_PATH:-}" ]; then
        if raw=$(sp_disk_layout_yaml_value "$SP_CONFIG_PATH" "installer.disk_layout.efi_size_mib" 2>/dev/null); then
            efi_size_override=$(sp_disk_layout_strip_quotes "$raw")
        fi
    fi
    if [ -z "$efi_alignment_override" ] && [ -n "${SP_CONFIG_PATH:-}" ]; then
        if raw=$(sp_disk_layout_yaml_value "$SP_CONFIG_PATH" "installer.disk_layout.efi_alignment_mib" 2>/dev/null); then
            efi_alignment_override=$(sp_disk_layout_strip_quotes "$raw")
        fi
    fi
    if [ -z "$root_alignment_override" ] && [ -n "${SP_CONFIG_PATH:-}" ]; then
        if raw=$(sp_disk_layout_yaml_value "$SP_CONFIG_PATH" "installer.disk_layout.root_alignment_mib" 2>/dev/null); then
            root_alignment_override=$(sp_disk_layout_strip_quotes "$raw")
        fi
    fi
    if [ -z "$root_reserved_override" ] && [ -n "${SP_CONFIG_PATH:-}" ]; then
        if raw=$(sp_disk_layout_yaml_value "$SP_CONFIG_PATH" "installer.disk_layout.root_reserved_mib" 2>/dev/null); then
            root_reserved_override=$(sp_disk_layout_strip_quotes "$raw")
        fi
    fi

    efi_size_mib=$(sp_disk_layout_to_int "$efi_size_override" 512)
    efi_alignment_mib=$(sp_disk_layout_to_int "$efi_alignment_override" 1)
    root_alignment_mib=$(sp_disk_layout_to_int "$root_alignment_override" 1)
    root_reserved_mib=$(sp_disk_layout_to_int "$root_reserved_override" 4)

    plan=$(sp_plan_partition_entries "$target_disk" "$disk_bytes" "$efi_size_mib" "$efi_alignment_mib" "$root_alignment_mib" "$root_reserved_mib")
    if [ $? -ne 0 ]; then
        return 1
    fi

    SP_DISK_LAYOUT_LAST_PLAN="$plan"
    printf '%s
' "$plan"
}

sp_print_layout_plan() {
    target_disk="$1"

    if [ -z "$target_disk" ]; then
        if ! target_disk=$(sp_select_target_disk); then
            return 1
        fi
    fi

    sp_plan_gpt_layout "$target_disk"
}
