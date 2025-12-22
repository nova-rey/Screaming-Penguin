# Prioritizing Initramfs Runtime Lib⁣

## Findings

- `build/installer-initramfs/init` is the initramfs entrypoint: it sets up `SP_LOG_DEVICE`, defines the structured `sp_log` helpers, and mirrors the bulk of `installer/init/init.sh` (storage probes, config discovery, `sp_run_installer`, and the main runner). That script currently assigns `SP_RUNTIME_LIB_DIR` at lines 69‑83 to `"$SP_SCRIPT_DIR/../runtime/lib"`, so it always walks up from `build/installer-initramfs` into `build/runtime/lib` before sourcing helpers such as `config_discovery.sh`.
- The initramfs build already ships a local runtime tree under `build/installer-initramfs/runtime/lib` that contains duplicates of the scripts in `installer/runtime/lib` (e.g., `config_discovery.sh`, `rescue_mode.sh`). The goal of the initramfs is to run entirely from the bundled tree, but the current `SP_RUNTIME_LIB_DIR` assignment ignores this local copy and falls back to the parent runtime tree.
- The `tests/installer/test_initramfs_runtime_lib_path.py` unit test reproduces this mismatch: it creates both `installer-initramfs/runtime/lib/config_discovery.sh` and `runtime/lib/config_discovery.sh`, writes each with a distinct marker (`LOCAL_LIB` vs `PARENT_LIB`), and runs `. build/installer-initramfs/init` with `SP_SKIP_INIT_MAIN=1` and `SP_INIT_SCRIPT_PATH` pointing at the transient init script. Because the test sources the init script, it is also setting `SP_SKIP_INIT_MAIN` to prevent the heavy `main` logic from running; at the moment the test still passes because the sourced helpers echo `PARENT_LIB`, showing the script is picking the parent lib.
- The test thus proves both the reproduction path (local versus parent libs) and the desired behaviour: the locally bundled helper should run, not the sibling under `build/runtime/lib`. There is also an existing guard (`SP_SCRIPT_IS_SOURCED`/`SP_SKIP_INIT_MAIN`) to prevent running the full installer when sourced, but the new test flow needs a more dependable detection so that sourcing does not accidentally invoke `main` when CI sources the script instead of executing it.

## Implications

- We must change `build/installer-initramfs/init` so `SP_RUNTIME_LIB_DIR` prefers `"$SP_SCRIPT_DIR/runtime/lib"` when that directory exists, only falling back to `"$SP_SCRIPT_DIR/../runtime/lib"` when we build the initramfs in a consumer tree that lacks the bundled libs.
- The init script should log the resolved runtime lib path during bootstrap so CI logs clearly show which tree is active.
- Sourcing guards must catch the CI pattern (`. build/installer-initramfs/init` with `SP_INIT_SCRIPT_PATH` supplied) without relying exclusively on Bash/Zsh-specific globals, so the test can source the init script without triggering the installer logic.

## Verification hooks (Block C preview)

- `pytest -q tests/installer/test_initramfs_runtime_lib_path.py` should now see `LOCAL_LIB` in the output because the helper from the bundled runtime tree is executed.
- `make ci-smoke` will continue to verify the rest of the initramfs/bootstrap pipeline after the runtime lib preference shifts.
