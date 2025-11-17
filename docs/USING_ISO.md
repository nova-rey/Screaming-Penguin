# Using the ISO Installer

Screaming Penguin provides a hybrid `.iso` image for Windows, macOS, and Linux users.
This ISO boots via BIOS and UEFI and contains the same installer environment as the
raw `.img` path, but it does not include a preformatted CONFIG partition.

## 1. Burning the ISO

### Windows
Use Rufus or Ventoy:
- Select `screaming-penguin.iso`
- Burn normally (no special options required)

### macOS
Use balenaEtcher or `dd`.

### Linux
Use `dd`, GNOME Disks, or Ventoy.

## 2. Creating the CONFIG Partition (Required)

Because ISO images cannot embed writable partitions, you must create a CONFIG
partition on the USB stick after flashing the ISO.

### Windows (Disk Management)
1. Open Disk Management
2. Right-click the main USB volume → "Shrink Volume"
3. Shrink by 1 GB (or more)
4. Create new simple volume in unallocated space
5. Format FAT32, label `CONFIG`
6. Copy your `installer-config.yml` into the new partition

### Linux
Use `gparted`, `parted`, or `fdisk`:
- Shrink the ISO filesystem partition
- Create new partition (1 GB or more)
- Format FAT32 (`mkfs.fat -F32`)
- Label `CONFIG`
- Copy YAML config

## 3. Booting

Once the CONFIG partition contains a valid YAML config file, boot the USB stick.
The installer will locate `/config/installer-config.yml`, validate it, and run.

## Troubleshooting

- If installer says “CONFIG not found,” verify:
  - The partition label is exactly `CONFIG`
  - The filesystem is FAT32
  - The YAML file is placed at the top level
