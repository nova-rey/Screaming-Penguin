# MP: fix initramfs runtime lib priority

## Findings
- `build/installer-initramfs/init` is the staged init script that gets copied from `installer/init/init.sh` via `tools/build_installer_initramfs.sh`; any change must be made at the source so future builds stay consistent.
- The script currently uses `SP_INIT_SCRIPT_PATH` (defaulting to `$0`) to compute `SP_SCRIPT_DIR`, so when the test sources the file `bash -c '. build/installer-initramfs/init'`, `$0` is the parent shell and the path inference is wrong for paths that rely on being relative to the script directory.
- `SP_RUNTIME_LIB_DIR` always points to `../runtime/lib`, so even when a runtime library is packaged adjacent to the init script (e.g., `init/runtime/lib`), the test expects that local directory to win; the current behavior reads from the parent `runtime/lib` instead.

## Planned edits
- Update `installer/init/init.sh` so it honors a new `SP_INIT_PATH` hint when set (used by tests when sourcing) and otherwise keeps the existing boot-time logic for `SP_SCRIPT_DIR`.
- Change the runtime library selection to prefer `"$SP_SCRIPT_DIR/runtime/lib"` if it exists, falling back to `"$SP_SCRIPT_DIR/../runtime/lib"` only when the local directory is absent.
- Mirror these changes in `build/installer-initramfs/init` so the staged init script matches, keeping the rest of the script untouched.
- Adjust `tests/installer/test_initramfs_runtime_lib_path.py` to set `SP_INIT_PATH` when invoking the init script so the source-safe path is used and the local runtime/lib directory is detected first.
