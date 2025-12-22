# MP Fix Initramfs Runtime Lib

## Initramfs entrypoint & runtime library resolution

- `build/installer-initramfs/init` is the POSIX bootstrap that ends up inside the initramfs. It derives `SP_SCRIPT_DIR` from `SP_INIT_SCRIPT_PATH` and immediately sets `SP_RUNTIME_LIB_DIR` to `"$SP_SCRIPT_DIR/../runtime/lib"`, so it always sources the parent installer runtime even when a `runtime/lib` tree is bundled alongside this init helper.

- The expectation is that the initramfs can ship a private `runtime/lib` beside `init`, but the bootstrap never checks for that first. As soon as libs load, the bootstrap drives disk discovery, readiness, and (if allowed) partition + deployment flows from that parent tree.

## Confirming the bug via tests

- `tests/installer/test_initramfs_runtime_lib_path.py` exercises the bootstrap by populating a temp `installer-initramfs/runtime/lib` (which prints `LOCAL_LIB`) and a sibling `<tmp>/runtime/lib` (which prints `PARENT_LIB`). It then sets `SP_INIT_SCRIPT_PATH` to the temp installer tree, forces `SP_SKIP_INIT_MAIN=1`, and runs `. build/installer-initramfs/init`.

- Because the bootstrap unconditionally points `SP_RUNTIME_LIB_DIR` at `../runtime/lib`, the parent script is sourced and the test sees `PARENT_LIB` instead of the local string. That proves the runtime/lib priority logic needs to look for a local tree before falling back.

## Sourcing detection

- The test sources the init script, so the bootstrap must recognize that and avoid calling `main`. The script already seeds `SP_SCRIPT_IS_SOURCED` via `BASH_SOURCE`/`ZSH_EVAL_CONTEXT`, but a more general guard is needed to cover plain `/bin/sh` contexts that CI might invoke.

- The plan is to derive a canonical path comparison between `$0` and `SP_INIT_SCRIPT_PATH` so a mismatch reliably indicates the file was sourced (and not executed), then avoid calling `main` when sourcing is detected.

## Next steps

- Prefer `$SP_SCRIPT_DIR/runtime/lib` when it exists and only fall back to `../runtime/lib` otherwise.
- Emit a `[SP-INSTALLER] state=bootstrap runtime_lib_dir=…` marker after resolution for easier CI visibility.
- Harden the sourcing guard so `. build/installer-initramfs/init` can be used from any POSIX shell without accidentally running the installer logic.
