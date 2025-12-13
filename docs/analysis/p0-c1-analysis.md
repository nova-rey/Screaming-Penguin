# P-0 C-1 Analysis

## Repository scan
- Top level already hosts `assets`, `build`, `dist`, `docs`, `initramfs_root`, `scripts`, `tools` plus tooling README/entrypoints but no `tests` directory, so new Ouroboros scaffolding must live under `ouroboros/` alone.
- Running `pytest -q` currently unknown; no pytest config files visible, so plan for a graceful failure note after running it in Block C.
- Existing `ouroboros/docs/ouroboros-overview.md` documents current project, so we will add the new analysis file without touching the root README or mainline assets.

## Assumptions validated
- This branch focuses on the "Ouroboros ISO" concept that copies boot media into RAM, reimages only the USB with a prebuilt `.img`, then restarts; we will not implement destructive behavior yet and keep everything under `ouroboros/` in isolation.
- Safety expectations are met by ensuring dry-run defaults, gating destructive actions (with `OUROBOROS_ENABLE_DESTRUCTIVE=1` + confirmation), and leaving only scaffolding for future ISO production.
- Initramfs scripts must use POSIX shell and mount `/proc`, `/sys`, `/dev` before delegating to the reimage script, dropping to a shell on failure.

## Required deliverables
- Directories: `ouroboros/` plus child folders `build/`, `dist/`, `docs/`, `initramfs_root/`, `scripts/`, `tools/`; plus `docs/analysis/` (created now).
- Files: `ouroboros/README.md`, `ouroboros/.gitignore`, `ouroboros/docs/ouroboros-overview.md`, `ouroboros/scripts/{detect_boot_device.sh,sanity_checks.sh,reimage_usb_from_ram.sh}`, `ouroboros/initramfs_root/init`, `ouroboros/tools/make_ouroboros_iso.sh`, and `.gitkeep` placeholders under `build/` & `dist/`.
- Scripts must document safety gates, detection must prefer by-label and abort on uncertainty, reimage script must default to dry-run and only expose destructive commands under the explicit env flag + confirmation string, and all bash scripts must set `set -euo pipefail` while initramfs scripts stay POSIX.

## Implementation plan
1. Create the `ouroboros/` directory tree plus `.gitkeep` files; add a scoped `.gitignore` that prevents build/dist cruft from leaking but leaves space for tracked sources.
2. Write `ouroboros/README.md` and `ouroboros/docs/ouroboros-overview.md` describing the concept, safety posture, and next steps to keep the feature isolated.
3. Craft toolbox scripts:
   - `detect_boot_device.sh` (bash) that looks up the desired label via `blkid`, aborts if zero/ambiguous devices, and prints the discovered path for consumers.
   - `sanity_checks.sh` (bash) that ensures necessary commands (`blkid`, `lsblk`, etc.) exist and fails fast otherwise, documenting the dry-run nature.
   - `reimage_usb_from_ram.sh` (bash) that sources `sanity_checks`, calls `detect_boot_device`, defaults to dry-run messaging, and guards destructive commands through `OUROBOROS_ENABLE_DESTRUCTIVE=1` plus a required confirmation string, with actual `dd` or `sgdisk` lines only included as commented examples for future use.
4. Build the initramfs stub: `ouroboros/initramfs_root/init` (POSIX sh) mounts `/proc`, `/sys`, `/dev`, executes the reimage script (if present), and on any failure falls into a shell to avoid halting.
5. Provide a builder stub at `ouroboros/tools/make_ouroboros_iso.sh` that sets up `build/` and `dist/`, echoes the future steps (copying files, generating initramfs, creating ISO), but stops short of actual ISO production.
6. Ensure all executable scripts are marked +x and all new files are created in full-file mode; keep the root README untouched.
7. After implementation, run `pytest -q` (even if it reports "no tests" or fails) and document the outcome, then verify no additional CI/doc updates are required.
