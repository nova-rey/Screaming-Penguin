# SP-P? — OPTION-B MDEV + IMMORTAL RESCUE ANALYSIS

## Block A Findings

- **PID 1 entrypoint**: `/init` is provided by `installer/init/init.sh`, which currently mounts proc/sys/devtmpfs, loads runtime helpers, and immediately runs `sp_discover_config` before any explicit `/dev` population. There is no later call to `mdev`, and the bootstrap helper only mounts devtmpfs, so on a hardware boot with no udev, `/dev/sdX1`/`/dev/mmcblk0p1`/`/dev/nvme0n1p1` never appear despite the kernel exposing the devices via `/sys`.
- **Rescue helper**: `installer/runtime/lib/rescue_mode.sh` `exec`s a shell once, binding stdio to `/dev/console`. If the shell exits (e.g., user exit or script recursion), PID 1 dies and the kernel panics. There is no loop or restart logic to keep init alive.
- **Config discovery helper**: `installer/runtime/lib/config_discovery.sh` prefers `/dev/disk/by-label`, then uses sysfs enumeration to try each `/dev/<partition>` candidate. Config discovery assumes the corresponding `/dev/...` node already exists, so when `/dev` is sparse it fails early and immediately drops into rescue mode.
- **Initramfs builder**: `tools/build_installer_initramfs.sh` stages BusyBox and symlinks only `sh`, `mount`, `mkdir`, `echo`, and `sleep`, with no explicit guard that `mdev` is available. If the build host’s BusyBox lacks `mdev`, the initramfs will never be able to populate `/dev`.

## Root causes

1. BusyBox-only initramfs boots with a minimal `/dev` (only console, null, zero, etc.), because devtmpfs alone does not magically create partition nodes when no udev runs. Without running `mdev -s` (or an equivalent), config discovery never sees `/dev/sdX1` nodes, so it assumes the installer config is missing.
2. Rescue mode tricks the kernel into running an interactive shell as PID 1 by `exec`ing into it. The shell controls PID 1; exiting it means PID 1 exits and the kernel panics even though rescue mode claims to exist to avoid that exact scenario.
3. The initramfs builder does not assert that `mdev` exists in the BusyBox it stages, so packaging could silently drop the new helper and the early-boot logic would still fail.

## Planned changes

1. **`installer/init/init.sh`:** Add `sp_bootstrap_dev_nodes` called after mounting proc/sys but before config discovery. This helper should:
   - Mount devtmpfs (best effort) if not already mounted and create `/dev/console` if missing.
   - Run `/bin/busybox mdev -s` (or `$MDEV_BIN -s`) to enumerate devices; no fatal error if `mdev` is missing.
   - Possibly re-run if desired, but at minimum assure `/dev` contains the block nodes that sysfs lists.
2. **`installer/runtime/lib/rescue_mode.sh`:**
   - Bind stdio to `/dev/console` (or test override) and run the shell in a restart loop, logging each exit and pausing briefly before continuing.
   - Keep the existing diagnostics (dump sysfs/`/proc/partitions`, label list), but replace the single `exec` with a `while true; do ...; done` loop so PID 1 never dies.
3. **`installer/runtime/lib/config_discovery.sh`:**
   - Make discovery succeed when only raw `/dev/<partition>` entries exist by enumerating `/sys/block` and building partition names (`sdX` → `/dev/sdX1`, `mmcblkN` → `/dev/mmcblkNp1`, `nvme0n1` → `/dev/nvme0n1p1`), just like the current partition loop but not relying on label directories.
   - Ensure each mount attempt is logged and `installer-config.yml` checked to mark success.
4. **`tools/build_installer_initramfs.sh`:**
   - After staging BusyBox, assert `busybox --list` includes `mdev`, or that the staged binary can run `mdev -s`. Fail the build if the applet is absent.
5. **Tests (`tests/installer`):**
   - Add a BusyBox init test verifying `sp_bootstrap_dev_nodes` triggers `mdev -s` before config discovery (using stub `mdev` binary).
   - Add a rescue-mode test that uses `SP_TEST_RESCUE_SHELL` to exit immediately and assert the loop restarts the shell (observe at least two invocations without PID 1 exiting).
   - Add a config discovery test that omits `/dev/disk/by-label` and only provides `/sys/block` plus synthetic `/dev` nodes, verifying discovery succeeds with the fake `installer-config.yml`.
6. **Docs & checklist:**
   - Update a doc (likely `docs/INITRAMFS.md` or `docs/BOOTFLOW.md`) to explain the BusyBox early-boot device node model, why `/dev/disk/by-label` is not assumed, and why rescue mode must keep PID 1 alive.
   - Mark the relevant checkpoint in `PHASE_CHECKLIST.md` (e.g., add a new row for this hotfix) to show the work was completed.

## Block B/C readiness

With the helper plan above, Block B will cover script/content changes plus adding deterministic tests without touching real devices. Block C will run `pytest -q`, `ruff check .`, `black --check`, and `shellcheck -x` on modified scripts, then append an “Evidence” section here summarizing changed files and tests for the two critical behaviors.
