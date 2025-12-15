# CI Workflows

## CI Smoke (PR + Push)

`CI Smoke` is the pull-request-friendly validation lane defined in `.github/workflows/ci.yml`. It runs on `pull_request` plus pushes to `main`, `master`, `develop`, and `**/feature/**` branches. The job:

- installs ShellCheck and Python tooling
- runs `make ci-smoke`, which executes:
  - `shellcheck tools/*.sh`
  - `python3 -m compileall -q .`
  - `pytest -q tests/installer -m "not needs_console and not needs_real_modules"`
- optional `ruff` / `black` checks when their configs are present

The smoke lane keeps the runner hermetic by excluding the few installer tests that need access to `/dev/console` or `/lib/modules/$(uname -r)`. Those cases are marked with `needs_console` and `needs_real_modules` in `pytest.ini` (for example, `tests/installer/test_bootstrap_dev_nodes.py`, which runs `sp_bootstrap` and `sp_validate_kernel_modules`) and will be skipped automatically when those prerequisites are missing.

This job uses `timeout-minutes: 30` so it always finishes quickly, and it relies on `tools/ci_smoke.sh` to keep the command sequence consistent for local runs.

## Full ISO Build (Workflow Dispatch / Nightly)

The full ISO build now lives in `.github/workflows/ci-iso-build.yml`. It only runs when explicitly triggered (`workflow_dispatch`) or once nightly (`cron: 0 3 * * *`). The job is bounded (`timeout-minutes: 150`) and each major stage is executed with:

- `timeout` wrappers plus `tools/ci_heartbeat.sh` to emit progress (runtime build, installer initramfs, ISO assembly)
- stage logging that appends to `ci-debug-summary.txt`
- a failure-only artifact upload that bundles `build/`, `dist/`, and the debug summary for faster triage

Use `make ci-iso` (or `bash tools/ci_iso.sh`) locally to replay the same three-stage sequence used by this workflow.

## Local Commands

- `make ci-smoke` — Run the smoke suite locally; helpful when you want to mirror the PR job before pushing. The marker filter keeps `/dev/console` and host `/lib/modules` out of the hermetic lane.
- `make ci-iso` — Run the runtime + initramfs + ISO stages locally. The wrapper will skip the redundant initramfs build inside `tools/make_installer_iso.sh` because it sets `SP_SKIP_INSTALLER_INITRAMFS_BUILD=1`.

To exercise the device-dependent coverage that `ci-smoke` skips, run `pytest tests/installer` directly on a host that provides `/dev/console` and `/lib/modules/$(uname -r)`. You can also target just those tests with `pytest tests/installer -m "needs_console or needs_real_modules"`.
If you need to keep a long-running step alive inside your own scripts, use `tools/ci_heartbeat.sh --label "<stage>" --interval <seconds> -- <command>` to emit regular heartbeat lines and make GitHub Actions aware of progress.
