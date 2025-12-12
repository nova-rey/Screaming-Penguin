#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="$root_dir/build"
dist_dir="$root_dir/dist"

mkdir -p "$build_dir" "$dist_dir"

echo "[make_ouroboros_iso] Build directory: $build_dir"
echo "[make_ouroboros_iso] Distribution directory: $dist_dir"

echo "[make_ouroboros_iso] Verifying required inputs..."
for path in "$root_dir/initramfs_root/init" "$root_dir/scripts/reimage_usb_from_ram.sh"; do
  if [ ! -f "$path" ]; then
    echo "[make_ouroboros_iso] WARNING: Expected file $path is missing. Stubbing ISO generation anyway." >&2
  fi
done

cat <<'DESC'
[make_ouroboros_iso] This is a stub build.
 - Future steps will copy initramfs content to $build_dir/initramfs
 - Future steps will stage scripts and docs under $build_dir/oem
 - Future steps will run xorriso/genisoimage to produce an ISO in $dist_dir
DESC

echo "[make_ouroboros_iso] No ISO is produced in this checkpoint. Build artifacts stay in $build_dir and $dist_dir for later." 
