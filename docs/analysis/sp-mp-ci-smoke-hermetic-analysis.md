# SP-MP CI Smoke Hermetic Analysis

## Block A Observations
- `shellcheck tools/*.sh` currently raises `SC2317` on `tools/ci_heartbeat.sh` because the cleanup block is only triggered via a trap; ShellCheck sees the `cleanup` lines as unreachable until the function is invoked explicitly (trap-only usage).
- `pytest tests/installer` cannot finish on the agent runner: `installer/init/init.sh` reaches `sp_bootstrap` before the suite can progress, forcing an unconditional write to `/dev/console` and calling `sp_validate_kernel_modules`, which insists on `/lib/modules/$(uname -r)` being present. The sandbox lacks both a writable `/dev/console` and matching kernel modules, so `tests/installer/test_bootstrap_dev_nodes.py` fails early.

## Hermetic Smoke Policy (Draft)
- `ci-smoke` must run only the tests that do not depend on host devices or module directories. Introduce markers such as `needs_console` and `needs_real_modules` for the few tests that rely on the real `/dev/console` or `/lib/modules`.
- The smoke script should select `pytest tests/installer -m "not needs_console and not needs_real_modules"` so GitHub runners skip device-dependent coverage.
- Each marked test should also check for the required device tree at runtime and call `pytest.skip(...)` when prerequisites are missing so a full suite run remains resilient.
