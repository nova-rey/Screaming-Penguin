# Using the IMG Installer

The `.img` artifact is designed for Linux users and power users who prefer a raw block
image. This path automatically includes a prebuilt CONFIG partition.

## 1. Flashing the IMG

Linux:
```bash
sudo dd if=screaming-penguin.img of=/dev/sdX bs=4M status=progress
sync
```

macOS:
Use dd or balenaEtcher.

Windows:
Not recommended; use the ISO path instead.

## 2. CONFIG Partition

The .img includes a preformatted FAT32 CONFIG partition.
Mount it, place your installer-config.yml inside, and boot.

## 3. Booting

Once the USB contains a config file, boot normally.
The installer will detect /config/installer-config.yml automatically.
