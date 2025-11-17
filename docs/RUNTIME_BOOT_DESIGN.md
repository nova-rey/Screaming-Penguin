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
5. `.img` builds remain unchanged and do not rely on this runtime.

## Expected Build Chain

make runtime   →   produces build/runtime/{vmlinuz, initrd.img}
make iso       →   consumes build/runtime and generates .iso
make dist-release → bundles both .img and .iso artifacts

## Notes

- Runtime generation is internal to developer workflows and CI; end-users do not interact with it.
- The installer logic itself does not change as part of this phase.

