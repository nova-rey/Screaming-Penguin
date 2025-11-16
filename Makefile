# Screaming Penguin - Makefile

.PHONY: iso rootfs clean qemu-acceptance

iso:
	@echo "[MAKE] Building Screaming Penguin installer image…"
	sh tools/make_installer_iso.sh

rootfs:
	@echo "[MAKE] Building Debian rootfs (bookworm-amd64)…"
	sh tools/build_debian_rootfs.sh

clean:
	@echo "[MAKE] Cleaning build and dist artifacts…"
	rm -rf build/*
	rm -rf dist/*

qemu-acceptance:
	@echo "[MAKE] Running QEMU acceptance harness…"
	sh tests/harness/qemu-acceptance.sh

