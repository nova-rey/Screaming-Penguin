# Screaming Penguin — Boot Flow

This document outlines the installer boot sequence and the fixes applied after the initramfs recovery.

---

## Standard Boot Path

- Kernel load → initramfs unpack → `/init` (BusyBox applet) → Screaming Penguin bootstrap.
- Installer bootstrap emits serial banners and the **"[SP-INSTALLER] init reached"** marker during early init.

## Failure Mode (Pre-Fix)

- Kernel reached **"Run /init as init process"** but `/init` was not executable inside the initramfs.
- Fallback init paths exhausted, leading to a kernel panic with no installer marker or serial breadcrumbs.

## Stabilized Path (Post-Fix)

- Initramfs verified to contain executable `/init` and BusyBox before QEMU launch.
- Serial stabilizer flushes QEMU logs to ensure visibility before timeouts.
- Successful boots always present the installer marker, confirming the init pipeline is running.
