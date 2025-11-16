# Screaming Penguin — Release Process (v1.0.0)

This document describes the human-driven process for cutting a Screaming
Penguin release from the main branch. It focuses on v1.0.0, but the same
pattern can be reused for future versions.

---

## 1. Pre-Release Checklist

Before tagging a release:

- Ensure `VERSION` is set to the desired version (e.g. `1.0.0`).
- Ensure `docs/RELEASE_NOTES_vX.Y.Z.md` exists and is up to date.
- Confirm that `docs/GETTING_STARTED.md`, `INSTALLER_USAGE.md`,
  `CONFIG_REFERENCE.md`, `SAFETY.md`, and `TROUBLESHOOTING.md` describe the
  current behavior accurately.
- Run CI:
  - Main CI workflow
  - dist-release CI (optional but recommended)
  - QEMU acceptance CI (optional but recommended)

---

## 2. Build Release Artifacts

From a clean working tree on the release commit:

```sh
make dist-release

This should produce:
	•	dist/release/screaming-penguin-vX.Y.Z.img
	•	dist/release/debian-rootfs-bookworm-amd64-vX.Y.Z.tar.gz
	•	dist/release/example-configs/
	•	dist/release/SHA256SUMS

Verify checksums:

cd dist/release
sha256sum -c SHA256SUMS


⸻

3. Create the Git Tag

Tag the release commit:

git tag -s vX.Y.Z -m "Screaming Penguin vX.Y.Z"
git push origin vX.Y.Z

If GPG signing is not configured, use:

git tag vX.Y.Z
git push origin vX.Y.Z


⸻

4. Create GitHub Release

On GitHub:
	1.	Navigate to “Releases”.
	2.	Click “Draft a new release”.
	3.	Choose tag vX.Y.Z (or create from the UI).
	4.	Set the release title (e.g. Screaming Penguin vX.Y.Z).
	5.	Attach artifacts from dist/release/:
	•	screaming-penguin-vX.Y.Z.img
	•	debian-rootfs-bookworm-amd64-vX.Y.Z.tar.gz
	•	example-configs archive (if created)
	•	SHA256SUMS
	6.	Paste the contents of docs/RELEASE_NOTES_vX.Y.Z.md as the body.

Publish the release.

⸻

5. Post-Release Notes
	•	Update roadmap and documentation for the next planned version.
	•	Optionally archive the dist/release/ directory or rebuild it if needed.
	•	Keep VERSION aligned with the latest stable release.

---
