# SP-MP CI Trace Hang Analysis

## Repository scan & current smoke setup
- The CI smoke lane is defined by `.github/workflows/ci.yml`; it runs `make ci-smoke` on every push to main, master, develop, and `feature/**` branches plus PRs, which keeps feedback fast (timeout 30 minutes).
- The workflow installs shellcheck and Python tooling via `apt-get install python3 python3-pip python3-pytest` and then upgrades pip before installing `ruff`, `black`, and `pyfatfs` with `python3 -m pip`.
- `tools/ci_smoke.sh` shells into the repo, runs `shellcheck` and `python3 -m compileall`, then `pytest -q` on `tests/installer` (filtered for fast smoke cases when `CI_SMOKE_FULL_INSTALLER=0`) under a `timeout` wrapping the whole session. It prints `[CI-SMOKE] ...` markers around the steps and optionally runs `ruff`/`black` when configs are present.

## Installer tests: unit-ish vs acceptance-ish
- **Acceptance-ish (touch real loop/dev resources)**
  - `tests/installer/test_disk_execute.py`: Creates a sparse file, attaches it via `sudo losetup`, runs the disk execute helpers, mounts the partitions via `mount`, and relies on `sgdisk`/`mount`/`umount`. This needs real loop devices and privileged utilities and therefore risks hanging/QEMU issues.
  - `tests/installer/test_installer_media_bootability.py`: Spawns `losetup`, `parted`, and `make_installer_img.sh` under `sudo`, manipulates GPT partitions, and inspects FAT32 images with `pyfatfs`. This is bordered by kernel interactions, so it is more acceptance than unit.
- **Unit-ish (simulate devices via stubs and temp dirs)**
  - `test_bootloader.py`, `test_bootstrap_dev_nodes.py`, `test_config_discovery_busybox.py`, `test_disk_layout_planner.py`, `test_init_write_gate.py`, `test_installer_initrd.py`, `test_kernel_module_identity.py`, `test_rescue_mode.py`, `test_rootfs_deploy.py`, `test_write_gate.py` all operate on fake paths, stubbed binaries, or just inspect generated configs without touching real loop devices or block mounts. They exercise logic deterministically and run quickly.

## Change plan
1. Keep the smoke job fast: keep the single `smoke` job in `.github/workflows/ci.yml`, ensure `python3-pip` is installed before using `python3 -m pip`, and use pip to install `pytest`, `pytest-timeout` (when present), and `pyfatfs` alongside the existing dev helpers. Export `PYTHONUNBUFFERED=1` and keep `CI_SMOKE_PYTEST_TIMEOUT_SECONDS` default at 600 but allow overrides so the outer `timeout` wrapper can still abort hung runs.
2. Improve `tools/ci_smoke.sh` so it prints clearly marked stages, runs a fast `python3 -m pytest -q --collect-only tests/installer` to fail early on missing deps, and runs the bounded installer suite with `-vv`, `--maxfail=1`, `--durations=25 --durations-min=0.5`, `-o console_output_style=progress`, and `PYTHONUNBUFFERED=1`. Detect whether `pytest-timeout` is installed (`python3 -c 'import pytest_timeout'`) and, if so, append `--timeout=60 --timeout-method=thread` to the pytest invocation so a wedged test fails fast while the outer `CI_SMOKE_PYTEST_TIMEOUT_SECONDS` still caps the total runtime.
3. Keep the current `-k` filters for the fast vs full installer selection; there is no existing marker strategy, so leave it as-is for now.
4. Document the new behavior in `docs/CI.md` (chatty pytest output, env vars, per-test timeout note), and add a short historical note in this analysis log so future readers know why the logs show the last test name and what to do when the suite times out.
5. After the changes, run `shellcheck tools/*.sh`, `python3 -m compileall -q .`, and `CI_SMOKE_PYTEST_TIMEOUT_SECONDS=60 bash tools/ci_smoke.sh` to prove the bounded behavior; capture those outcomes for the PR metadata.

## Historical note
- Pytest is now verbose so the last-emitted test name is always visible on failure/timeout, which makes it easier to pinpoint hung installer tests before the CI job gets killed.
- When `CI_SMOKE_PYTEST_TIMEOUT_SECONDS` fires, look at the final pytest progress line to see which test was running; if `pytest-timeout` is available the per-test timeout (`--timeout=60 --timeout-method=thread`) will also fail the individual test quickly and log its name.
