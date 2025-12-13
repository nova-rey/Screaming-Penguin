# QEMU Smoke Test

1. Build the ISO and initramfs:
   ```sh
   ./ouroboros/tools/make_ouroboros_iso.sh
   ```
2. Boot the resulting ISO in QEMU:
   ```sh
   timeout 120s qemu-system-x86_64 \
     -m 2048 -smp 2 -nographic -serial mon:stdio -no-reboot \
     -cdrom ouroboros/dist/sp-ouroboros.iso -boot d
   ```
   * `timeout` ensures the run exits once we confirm `/init` and the dry-run script execute.
   * The `-nographic -serial mon:stdio` flags let you watch the initramfs logs directly in your terminal.
3. Expect to see the following sequence:
   * `init` mounts `/proc`, `/sys`, `/dev` and prints `[init]` diagnostics.
   * `[reimage_usb_from_ram]` logs the detected boot device and notes that destructive work is skipped.
   * The reimage script exits with `0` because `OUROBOROS_ENABLE_DESTRUCTIVE` stays unset, then `init` drops to the shell.
4. When you see the dry-run completion message, QEMU will exit automatically at the `timeout`, or press `Ctrl-A X` if you want to stop it sooner.
