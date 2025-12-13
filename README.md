<p align="center">
  <img src="assets/logo/screaming-penguin.PNG" width="200" alt="Screaming Penguin Logo">
</p>
# Screaming Penguin

Screaming Penguin is a config-driven, automated Debian installer delivered as
either a raw `.img` (Linux-friendly) or a hybrid `.iso` (Windows/macOS-friendly).

See the `docs/` directory for full usage guides:

- `USING_IMG.md`
- `USING_ISO.md`
- `GETTING_STARTED.md`
- `INSTALLER_USAGE.md`
- `CONFIG_REFERENCE.md`

Both installer formats provide the same automated Debian runtime environment.
The IMG path includes a prebuilt CONFIG partition; the ISO path requires the
user to create one manually after flashing.

## Ouroboros variant

Ouroboros-specific scaffolding (initramfs, docs, scripts, and tools) now lives under `ouroboros/`.
See `ouroboros/README.md` and `ouroboros/docs/` for the ISO-focused work.
