# Phase 13 — Installer Media Bootability Analysis

## Current state
- `tools/make_installer_img.sh` today allocates one GPT disk image, but rather than building a real EFI boot tree it formats the first partition as `ext2`, copies placeholder `vmlinuz-sp`/`initrd.img-sp`, and writes a trivial `boot/grub.cfg` that never matches the real installer artifacts. Partition 2 remains the FAT32 `SP_CONFIG` volume as before.
- The installer ISO builder (`tools/make_installer_iso.sh`) already stages the actual runtime kernel (`build/runtime/vmlinuz`) and installer initramfs (`build/initrd-installer.img`), copies them into `dist/vmlinuz-installer` + `dist/initrd-installer.img`, and writes a more comprehensive GRUB config that knows about `/serial` consoles and the real `/boot/vmlinuz-installer`/`/boot/initrd-installer.img` pair.
- Runtime helpers (`installer/runtime/lib/bootloader.sh`) already expect an EFI partition in FAT32 format, find `/boot/vmlinuz` + `/boot/initrd.img` during install, and generate GRUB configs referencing those paths.

## Deficiencies (Phase 13 targets)
1. Phase 13 requires the `.img` artifact to be a genuine UEFI/BIOS boot USB, but the current boot partition is `ext2`, lacks an EFI System Partition label/flag, and never installs the real installer kernel/initramfs or GRUB EFI binary (`EFI/BOOT/BOOTX64.EFI`).
2. The placeholder `grub.cfg` misses the actual kernel/initrd names (`vmlinuz-installer`, `initrd-installer.img`) and does not live under `EFI/BOOT`; it also is not tested for FAT32 support or correct loader paths.
3. There is no shared template or helper to keep the `.img` and `.iso` GRUB paths in sync, so updates to the iso boot entry diverge from the raw image build.
4. Documentation and roadmaps still stop at Phase 12; no Phase 13 roadmap, contract entry, or schema note exists describing the need for a FAT32 ESP, a `BOOTX64.EFI`, or the minimal installer `grub.cfg`.

## Block B plan (Implementation)
- Rework `tools/make_installer_img.sh` to honor configurable overrides (e.g., `SP_IMG_SIZE`, `SP_IMG_BOOT_SIZE_MB`, `SP_IMG_CONFIG_SIZE_MB`, `SP_IMG_OUT`). Keep the default `IMG_SIZE=3G` but allow tests to build a smaller image. Truncate & label the image, create a GPT table, add:
  * Partition 1 → FAT32 `SP_CONFIG` (existing behavior, now deliberately placed first so users see `/config` without partition discovery grief).
  * Partition 2 → FAT32 EFI System Partition (set the `esp`/`legacy_boot` flags, format with `mkfs.vfat`, label `SP_BOOT` or similar).
- Build a proper boot tree under `$BUILD_DIR/boot`:
  * Copy `/boot/vmlinuz-installer` and `/boot/initrd-installer.img` from `dist/` (produced by the ISO build) or fallback to `build/runtime/vmlinuz` + `build/initrd-installer.img` when dist files are missing.
  * Create `EFI/BOOT/` and install the host-provided `grubx64.efi` (string path from `/usr/lib/grub/x86_64-efi/monolithic/grubx64.efi` or `/usr/lib/grub/i386-pc/` if only BIOS is available), and ensure `BOOTX64.EFI` exists (copy or symlink to the loaded EFI binary).
  * Stage `EFI/BOOT/grub.cfg` with the exact snippet required by Phase 13 (search for `/boot/vmlinuz-installer`, set default=0, timeout=0, include `linux /boot/vmlinuz-installer quiet`, `initrd /boot/initrd-installer.img`).
- Mount the FAT32 ESP (`P2_DEV`), copy the boot tree (`EFI/BOOT/` + `/boot/` contents), and also copy `grub.cfg` under `/boot/grub` if desired (to mimic old layout).
- Ensure Partition 1 is formatted FAT32 and kept reserved for `/config` data so the user-facing layout matches expectations.
- Factor the `grub.cfg` menu entry into a shared template (`tools/installer-grub.cfg`), letting both `tools/make_installer_iso.sh` and the `.img` builder include the same block to keep kernel/initrd arguments synchronized while still allowing the ISO script to prepend serial/terminal configuration.

## Block C plan (Verification)
- Add `tests/installer/test_installer_media_bootability.py` to:
  * Invoke the revamped `tools/make_installer_img.sh` with overridden env vars to produce a small test image (e.g., 64 MB + 16 MB boot) inside the test tmpdir.
  * Attach the image with `losetup`/`kpartx` (or `parted`) to locate partition nodes, mount the ESP, and verify the filesystem type is FAT32 (`fatlabel` or `blkid` output).
  * Assert the mounted ESP contains `/EFI/BOOT/BOOTX64.EFI`, that `/EFI/BOOT/grub.cfg` references `vmlinuz-installer` and `initrd-installer.img`, and that `/boot/vmlinuz-installer` + `/boot/initrd-installer.img` exist on the same partition.
- After cleaning, run the required verification suite:
  * `pytest -q`
  * `ruff check .`
  * `black --check installer tools tests`
  * `shellcheck -x tools/*.sh installer/init/init.sh installer/runtime/lib/*.sh`
  Ensure all commands pass before finalizing the phase.

## Documentation updates
- Record this analysis & plan in `docs/analysis/p13-installer-media-bootability-analysis.md` (this file).
- Introduce `docs/Phase13_Roadmap.md` describing the goal of producing a bootable image with FAT32 ESP, GRUB EFI, shared templates, and the tester script.
- Update `docs/DEV_ROADMAP.md`, `docs/architecture.md`, `docs/CONFIG_SCHEMA.md`, and `docs/installer_contract.md` to mention the new Phase 13 installer-media bootability requirements (EFI System Partition, `EFI/BOOT/BOOTX64.EFI`, `grub.cfg` contents, etc.).
- Add Bible entries (`docs/SP_BIBLE.md`, `docs/SCREAMING_PENGUIN_BIBLE.md`) marking Phase 13 completion so historical logs reflect the new bootable USB image.
- Document any new config options (if introduced) and link to the shared GRUB template so the ISO/.img builds stay aligned.

## Risks & dependencies
- Building the ESP depends on a host `grubx64.efi` binary. The script must fail fast if the expected path (`/usr/lib/grub/x86_64-efi/monolithic/grubx64.efi` or similar) is missing and instruct maintainers to install `grub-efi-amd64-bin`.
- The `.img` builder now requires the installer kernel/initrd artifacts produced by the ISO pipeline (`dist/vmlinuz-installer` + `dist/initrd-installer.img`), so CI must build them before running the `.img` script.
- Tests rely on loop device management (losetup/kpartx). The harness should clean up aggressively (trap cleanup) and skip sections if the required tools are unavailable to keep CI resilient.
