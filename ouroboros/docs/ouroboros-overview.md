# Ouroboros Overview

## Concept
The Ouroboros ISO boot path copies itself into RAM, reimages the USB boot media from a pre-built image, and reboots to the refreshed media. This repository structure keeps Ouroboros-specific files under `ouroboros/` so Screaming Penguin mainline code stays untouched.

## Non-goals in this checkpoint
1. No actual ISO generation or USB flashing occurs yet.
2. No rewriting of Screaming Penguin core sources.
3. No CI changes or new system dependencies are introduced.

## Safety guarantees
- Default behavior is dry-run, logging each step without executing destructive commands.
- Real disc writes only run when `OUROBOROS_ENABLE_DESTRUCTIVE=1` **and** the operator types the exact confirmation string when prompted.
- Boot device detection uses filesystem labels and fails rather than guessing by `/dev/sdX` ordering.
- Initramfs `init` mounts required virtual filesystems, calls the reimage entrypoint, and drops to an interactive shell on any failure, preventing silent halts.

## Future work hints
- `tools/make_ouroboros_iso.sh` will grow into a full ISO builder that stages the initramfs, `ouroboros/scripts/` assets, and the final ISO in `dist/`.
- `scripts/sanity_checks.sh` can be extended with environment validation before any reimage attempt.
- `initramfs_root/init` will eventually be packaged into the bootable image shown to users.
