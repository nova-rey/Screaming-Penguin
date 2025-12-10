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

## Installer Artifacts: .img vs .iso

Screaming Penguin currently ships two primary artifacts:

- A raw disk image: `screaming-penguin.img`
- A hybrid ISO: `screaming-penguin.iso`

As a rule of thumb:

- **Linux / macOS** users who are comfortable with `dd`, `lsblk`, and
  basic disk tools should prefer the **`.img`**. It writes directly to a
  USB device and produces a bootable stick with a separate `CONFIG`
  partition ready for `installer-config.yml`.

- **Windows** users, and anyone who prefers GUI USB tools such as Rufus,
  can use the **`.iso`**. After flashing the ISO to a USB stick, you will
  create the `CONFIG` partition manually (see below) and drop your
  `installer-config.yml` there.

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

## ISO Builds in CI

The CI pipeline now produces both:

- `screaming-penguin.img`
- `screaming-penguin.iso`

ISO builds are recommended for Windows/macOS users.
