# Screaming Penguin — Getting Started (v1.0.0)

Screaming Penguin is a deterministic, configuration-driven Debian installer
designed for automated, headless, or unattended deployments. It wipes a target
disk, extracts a prebuilt Debian Bookworm root filesystem, and applies system
settings based on a YAML configuration file located on a writable `/config`
partition of the installer USB.

This guide covers the minimum steps required to perform a successful v1.0.0
installation.

---

## 1. System Requirements

- x86_64 CPU
- BIOS or UEFI firmware
- One target disk (NVMe or SATA)
- Ability to boot from USB
- USB stick of 2GB or larger

---

## 2. Download Release Files

From the Screaming Penguin GitHub Release page download:

- `screaming-penguin-v1.0.0.img`
- `debian-rootfs-bookworm-amd64-v1.0.0.tar.gz`
- `example-configs/` bundle
- `SHA256SUMS`

Verify checksums using:

```sh
sha256sum -c SHA256SUMS
```

## Installer Artifact

Screaming Penguin ships a single installer image: `screaming-penguin.img`. The
image includes a preformatted `CONFIG` partition so you can flash it, mount
`/config`, and immediately drop your `installer-config.yml` + rootfs tarball
without additional partition juggling. The hybrid ISO build has been pruned from
this repository; historical instructions remain in `docs/USING_ISO.md`, but any
modern ISO path lives in the external Ouroboros side project.

⸻

3. Write Installer Image to USB

On Linux:

sudo dd if=screaming-penguin-v1.0.0.img of=/dev/sdX bs=4M status=progress
sudo sync

Replace sdX with your USB device.

On Windows:
Use Rufus or Balena Etcher.

On macOS:

sudo dd if=screaming-penguin-v1.0.0.img of=/dev/diskX bs=4m
sync


⸻

4. Prepare the /config Partition

After imaging, unplug/reinsert the USB so its writable first partition (the `/config` volume) appears.

Place:

/config/installer-config.yml
/config/rootfs/debian-rootfs.tar.gz

installer-config.yml must conform to the schema described in
CONFIG_REFERENCE.md.

⸻

5. Boot Target Machine
1.Insert USB into the destination machine.
2.Boot from USB.
3.Screaming Penguin will:
•Validate configuration
•Verify rootfs presence
•Verify target disk exists
•Confirm erase word (if required)
•Partition the disk (EFI + ext4)
•Extract rootfs
•Configure hostname, locale, timezone, users, SSH, GRUB
•Log all actions to /config/logs/

On success the machine will shut down or reboot depending on config.

⸻

6. Logs

Logs persist on the USB under:

/config/logs/installer-YYYYMMDD-HHMMSS.log

These logs are critical for debugging installation issues.

⸻

7. Example Configs

See config/examples/ or the release bundle’s example-configs directory.

⸻

8. Next Steps

Proceed to INSTALLER_USAGE.md for detailed workflow and troubleshooting.

---

## Artifact Builds in CI

The CI pipeline now produces only the canonical `.img` artifact (`dist/screaming-penguin.img`). Smoke builds and tests validate the GPT layout, ESP contents, and kernel/initrd references without ever booting the media. ISO builds have been pruned from this repository; see `docs/analysis/sp-mp-prune-iso-analysis.md` for the rationale and follow the Ouroboros side project for any hybrid ISO needs.
