# SP-MP CI Trace Hang Verification

## Commands
1. `shellcheck tools/*.sh` — passes (exit code 0).
2. `python3 -m compileall -q .` — passes (exit code 0).
3. `CI_SMOKE_PYTEST_TIMEOUT_SECONDS=60 bash tools/ci_smoke.sh` — aborted when `tests/installer/test_bootstrap_dev_nodes.py::test_bootstrap_runs_mdev_before_config_discovery` failed because the sandbox could not talk to `/dev/console` or the matching kernel modules directory. Pytest still produced the verbose progress output that exposes each running test before the failure.

## Notable output (command 3)
```
[CI-SMOKE] pytest collection-only succeeded
[CI-SMOKE] pytest timeout=60s target=tests/installer
============================= test session starts ==============================
...collecting ... collected 36 items

tests/installer/test_bootloader.py::test_bootloader_generates_fstab PASSED [  2%]
...
tests/installer/test_bootstrap_dev_nodes.py::test_bootstrap_runs_mdev_before_config_discovery FAILED [ 13%]
=================================== FAILURES ===================================
installer/init/init.sh: line 353: /dev/console: Permission denied
[SP-INSTALLER] FATAL kernel/modules mismatch: running kernel=6.8.12-13-pve requires /lib/modules/6.8.12-13-pve
```

## Observations
- The collection-only pass runs before the bounded suite, matching the new script behavior.
- Verbose pytest output (`-vv`, progress-style) is visible and identifies the last test before the failure, so a hanging test will be easy to spot.
- `pytest-timeout` is absent in this environment, so the per-test `--timeout` flags were skipped in this run.
