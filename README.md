# Screaming Penguin

Screaming Penguin is a deterministic, configuration-driven automated Debian
installer designed for headless environments, homelabs, labs, and unattended
deployments. It installs a prebuilt Debian Bookworm root filesystem onto a
target disk using a YAML configuration stored on the USB's `/config` partition.

## Documentation

User-facing documentation for Screaming Penguin is located under the `docs/`
directory:

- `GETTING_STARTED.md`
- `INSTALLER_USAGE.md`
- `CONFIG_REFERENCE.md`
- `SAFETY.md`
- `TROUBLESHOOTING.md`

These documents provide detailed guidance for preparing the installer media,
supplying configuration, and troubleshooting installs.

## Release Packaging

Screaming Penguin provides a `make dist-release` target to assemble the v1.0.0
release bundle, including installer image, rootfs tarball, example configs, and
SHA256 checksums. See `docs/GETTING_STARTED.md` and
`docs/INSTALLER_USAGE.md` for details.

## Version

This repository is prepared for the v1.0.0 release of Screaming Penguin.
