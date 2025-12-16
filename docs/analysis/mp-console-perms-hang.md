# MP console-permissions hang

CI boots the installer with `/dev/console` and `/dev/ttyS0` owned by root, so the early `sp_bootstrap` marker write and the rescue shell that re-opens `/dev/console` immediately fail with “Permission denied.” `set -e` + redirections propagate the failure into rescue mode before the test can finish, and rescue_mode loops keep echoing the error while `pytest` waits on the hung installer.

This patch hardens two hotspots:
  * `installer/init/init.sh`: best-effort helpers (`sp_best_effort_redirect`, `sp_can_write`) gate the serial/log writes, the init marker goes to `SP_OUT_DEVICE`, and the idle shell falls back to stderr so `/dev/console` errors can never abort bootstrap.
  * `installer/runtime/lib/rescue_mode.sh`: `sp_rescue_console_fd_setup` reuses either `/dev/console` or stderr, and CI with no writable console now prints a single line and exits instead of looping with repeated permission failures.

Because the new helpers prefer the configured log device and only fall back when the console truly cannot be written, actual boot media still uses `/dev/console`/`/dev/ttyS0` as before while the CI runner avoids the hang.
