# Screaming Penguin ISO Runtime Notes

## 2025-11-18 — ISO now carries runtime + GRUB config

The `screaming-penguin.iso` image now includes the installer runtime payload and a GRUB configuration so it can boot directly on real hardware (not just via QEMU).

Changes:

- The installer kernel and initrd built under `build/runtime/` are copied into the ISO staging tree as:

  - `/boot/vmlinuz`
  - `/boot/initrd.img`

- `tools/make_installer_iso.sh` now writes `boot/grub/grub.cfg` with a single menu entry:

  - `linux /boot/vmlinuz ...`
  - `initrd /boot/initrd.img`

- The kernel command line used in `grub.cfg` is identical to the one used in `ci/qemu_smoke_ci.sh` (`SP_KERNEL_CMDLINE`), so USB boots and the QEMU smoke test exercise the same runtime behavior.

Result: USB sticks created from `screaming-penguin.iso` should no longer drop into a bare `grub>` shell and instead boot straight into the Screaming Penguin installer.
