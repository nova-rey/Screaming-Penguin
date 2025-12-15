# CI Workflows

## CI Smoke (PR + Push)

`CI Smoke` is the pull-request-friendly validation lane defined in `.github/workflows/ci.yml`. It runs on `pull_request` plus pushes to `main`, `master`, `develop`, and `**/feature/**` branches. The job:

- installs ShellCheck and Python tooling
- runs `make ci-smoke`, which executes:
  - `shellcheck tools/*.sh`
  - `python3 -m compileall -q .`
  - `pytest tests/installer`
  - optional `ruff` / `black` checks when their configs are present

This job uses `timeout-minutes: 30` so it always finishes quickly, and it relies on `tools/ci_smoke.sh` to keep the command sequence consistent for local runs.

## Full ISO Build (Workflow Dispatch / Nightly)

The full ISO build now lives in `.github/workflows/ci-iso-build.yml`. It only runs when explicitly triggered (`workflow_dispatch`) or once nightly (`cron: 0 3 * * *`). The job is bounded (`timeout-minutes: 150`) and each major stage is executed with:

- `timeout` wrappers plus `tools/ci_heartbeat.sh` to emit progress (runtime build, installer initramfs, ISO assembly)
- stage logging that appends to `ci-debug-summary.txt`
- a failure-only artifact upload that bundles `build/`, `dist/`, and the debug summary for faster triage

Use `make ci-iso` (or `bash tools/ci_iso.sh`) locally to replay the same three-stage sequence used by this workflow.

## Local Commands

- `make ci-smoke` — Run the smoke suite locally; helpful when you want to mirror the PR job before pushing.
- `make ci-iso` — Run the runtime + initramfs + ISO stages locally. The wrapper will skip the redundant initramfs build inside `tools/make_installer_iso.sh` because it sets `SP_SKIP_INSTALLER_INITRAMFS_BUILD=1`.

If you need to keep a long-running step alive inside your own scripts, use `tools/ci_heartbeat.sh --label "<stage>" --interval <seconds> -- <command>` to emit regular heartbeat lines and make GitHub Actions aware of progress.
