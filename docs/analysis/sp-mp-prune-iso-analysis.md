# SP-MP Prune ISO Analysis

## ISO Inventory
- `Makefile` still exposes `iso`, `ci-iso`, and `dist-release` targets that invoke `tools/make_installer_iso.sh` or copy `dist/screaming-penguin.iso`.
- `tools/make_installer_iso.sh`, `tools/ci_iso.sh`, and `ci/qemu_smoke_ci.sh` all reference `dist/screaming-penguin.iso` and grub/EFI tooling.
- `.github/workflows/{ci-iso-build,dist-release-ci,qemu-acceptance-ci}` run ISO build steps (runtime+initramfs+ISO, packaging, QEMU acceptance) automatically.
- `docs/*` (README, CI.md, CI_OVERVIEW.md, INSTALLER_USAGE.md, BOOT_PIPELINE.md, GETTING_STARTED.md, USING_ISO.md, architecture/SCREAMING_PENGUIN_BIBLE variants, etc.) still describe two artifact paths (`.img` and `.iso`).
- `tests/installer` contains ISO-specific tests (`test_make_installer_iso_*`, `test_iso_initrd_*`) and the QEMU harness/help scripts remind users to `make iso`.

## PR/CI Surface
- `ci.yml` currently only runs `make ci-smoke`, but older analysis shows ISO builds were part of PR CI (`make iso` + `ci/qemu_smoke_ci.sh`). The manual/nightly workflows (`ci-iso-build`, `qemu-acceptance`, `dist-release-ci`) still schedule heavy ISO/runtime stages.
- Any CI job that still invokes `make iso`, `tools/make_installer_iso.sh`, or `ci/qemu_smoke_ci.sh` would violate the new constraint: ISO must not run in PR CI and must be gated/manual.
- The smoke workflow should be minimal: shellcheck, `python3 -m compileall`, unit tests limited to non-boot coverage, optional `ruff/black`, and structural `.img` checks.

## .img Build State
- The canonical `.img` asset is built by `make img` → `tools/make_installer_img.sh`, which partitions an image, formats FAT32 CFG/ESP, copies `/boot/vmlinuz-installer` + `initrd-installer.img`, installs `grubx64.efi`, and drops a shared `grub.cfg` using `tools/grub_shared.sh`.
- `tests/installer/test_installer_media_bootability.py` already exercises GPT layout, FAT32 ESP, labels, and loader entries via `PyFatFS` without relying on ISO.
- `tests/harness/qemu-acceptance.sh` ingests `dist/screaming-penguin.img`, so post-PR CI we can continue using `.img` for acceptance scenarios.

## Removal Plan
1. Remove `iso`/`ci-iso` targets and any default chains that refer to `.iso` (e.g., `Makefile:dist-release`, `qemu-acceptance-ci`, `ci/qemu_smoke_ci.sh`) by either removing them or making them fail fast with a clear Ouroboros message.
2. Delete/retire `tools/make_installer_iso.sh` and `tools/ci_iso.sh`, or rewrite them to print `ISO builds disabled; use Ouroboros` while ensuring they do nothing when accidentally invoked.
3. Update `.github/workflows` so that no scheduled/push workflow builds ISO automatically; iso workflows may remain as manual `workflow_dispatch` stub (non-blocking) if still needed for Ouroboros reference. `qemu-acceptance-ci` should rely on `make img` only and skip iso tests.
4. Ensure every helper script (QEMU harness, docs) now refers to `.img` exclusively; append comments noting `ISO path intentionally removed; Ouroboros is the future home.

## .img Integrity Guardrails
- `make ci-smoke` will continue to run `shellcheck`, `python3 -m compileall -q .`, and limited pytest (installer/media tests) against `.img` so PR CI validates partition layout via deterministic checks.
- Tests will be updated to remove ISO coverage (the iso-specific tests will be deleted) and focus on verifying GPT, partition GUIDs, ESP contents, and `grub.cfg` entries produced by `tools/make_installer_img.sh`.
- Add documentation or helper script comments explaining that `.img` structural validation should fail fast if partitions/files are missing.

## Documentation Impact
- Update the core README/Getting Started/CI docs to state that `.img` is the sole supported artifact, ISO is deprecated (future via Ouroboros), and `make ci-smoke` is the fast PR surface while manual/long-running CI is handled elsewhere.
- Remove or reframe `docs/USING_ISO.md`/`docs/ISO_BUILD.md` references, noting that any remaining ISO instructions point to Ouroboros or future manual workflows.
- Annotate `docs/analysis` and other records mentioning ISO to indicate the path is pruned (e.g., add a note near `AGENT_RUNS` entries that iso jobs are now defunct).

With this analysis in place, Block B can proceed to remove ISO paths, strengthen `.img` validation, and refresh docs/CI references without regressions.
