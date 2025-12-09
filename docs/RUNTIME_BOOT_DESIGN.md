# Runtime Boot Design — Minimal Kernel + Initramfs

## Purpose

The Screaming Penguin ISO build path requires a minimal boot runtime containing:

- A Linux kernel (`vmlinuz`)
- An initramfs (`initrd.img`)

These files must be present under `build/runtime/` before `make iso` is executed.

## High-Level Plan

1. Use `debootstrap` to create a minimal Debian Bookworm chroot.
2. Install a generic kernel (`linux-image-amd64`) inside that chroot.
3. Extract:
   - `/boot/vmlinuz-*` → `build/runtime/vmlinuz`
   - `/boot/initrd.img-*` → `build/runtime/initrd.img`
4. The runtime is used **only** to boot the ISO and launch the installer.
5. `.img` now consumes the same kernel/initrd artifacts so both media builders stay aligned.

## Expected Build Chain

- `make runtime` → builds the kernel + initramfs, copies them into `build/runtime/` and `dist/`, and supplies the artifacts for every installer media path.
- `make img` → depends on the runtime build so `/dist/vmlinuz-installer` + `/dist/initrd-installer.img` (or the `build/` fallback) always exist before partitioning.
- `make iso` → also depends on the runtime build before invoking `tools/make_installer_iso.sh` so it reuses the same kernel/initrd pair.
- `make dist-release` → runs the runtime build first, then `.img`, then `.iso`, and finally packages the release bundle without missing artifacts.

## Notes

- Runtime generation is internal to developer workflows and CI; `make img`, `make iso`, and `make dist-release` now rely on this shared runtime step so all media builders stay in sync.
- The installer logic itself does not change as part of this phase.
