# Analysis: MP fix SP_INIT_PATH guard under `set -u`

## Files inspected for Block A
- `installer/init/init.sh` and its staged copy at `build/installer-initramfs/init` (the only places where `SP_INIT_PATH` is referenced).  Both files currently guard by `[ -n "${SP_INIT_PATH:-}" ]` but still call `dirname "$SP_INIT_PATH"` without a fallback.
- `tools/build_installer_initramfs.sh`, which runs with `set -euo pipefail`.  When this script stages the init entrypoint, any expansion of an unset `SP_INIT_PATH` would trip the nounset behavior.
- `tests/installer/test_installer_initrd.py` and `tests/installer/test_initramfs_runtime_lib_path.py`, which rely on the generated init script and, in the latter case, explicitly set `SP_INIT_PATH` so the logic runs in tests.

## Failure mode
`tools/build_installer_initramfs.sh` enables `set -u`, so every expansion of `$SP_INIT_PATH` must provide a default.  The init script uses an `if` guard of `${SP_INIT_PATH:-}` but still directly passes `"$SP_INIT_PATH"` to `dirname` when the guard is true.  During the initramfs build (and the associated regression test), `SP_INIT_PATH` is often not defined; under `set -u` that literal dereference becomes an "unbound variable" fatal, and `dirname` would moreover receive an empty operand if `SP_INIT_PATH` happens to be empty.  This aborts the build before the initramfs can be assembled.

## Conclusion
`SP_INIT_PATH` must remain optional.  The fix is to keep the current conditional but pass a safe default (e.g., `${SP_INIT_PATH:-}`) whenever `dirname` is invoked, so there is never an empty operand or nounset dereference.  The same change must also hit the staged copy at `build/installer-initramfs/init` because the build script copies the source verbatim into the initramfs root.
