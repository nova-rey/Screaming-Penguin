# Ouroboros ISO Scaffold

This directory holds the Ouroboros ISO concept: a bootable artifact that copies itself into RAM, performs a safe reimage of the boot USB, and reboots cleanly. This checkpoint only ships scaffolding. No destructive actions occur unless an operator explicitly enables them.

## Safety posture
- All scripts default to dry-run behavior and merely log their intent.
- Destructive tooling is gated by `OUROBOROS_ENABLE_DESTRUCTIVE=1` plus an explicit confirmation string.
- Boot device detection prefers label-based lookup and fails fast when devices are missing or ambiguous.
- Initramfs tooling mounts `/proc`, `/sys`, and `/dev`, then drops to a shell on errors instead of exiting silently.

## Layout
- `docs/` carries concept documentation and future intent.
- `scripts/` contains detection, sanity-check, and reimage helpers.
- `tools/` stores builder utilities (currently a stub).
- `initramfs_root/` outlines the init script that will run inside the ISO.
- `build/` and `dist/` are placeholders for future artifacts (kept empty via `.gitkeep`).
