# Screaming Penguin - Makefile

RUNTIME_DIR := build/runtime

.PHONY: img iso rootfs clean qemu-acceptance runtime

img:
	@echo "[MAKE] Building Screaming Penguin installer image…"
	sh tools/make_installer_img.sh

iso: runtime
	@echo "[MAKE] Building Screaming Penguin ISO…"
	bash tools/make_installer_iso.sh

.PHONY: runtime
runtime:
	@echo "[MAKE] Building minimal boot runtime…"
	bash tools/build_runtime.sh

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

# Phase 7 — Release Packaging
# Assemble installer ISO, rootfs tarball, example configs, and checksums into dist/release/

dist-release: img iso rootfs
	@echo "[DIST] Assembling v1.0.0 release directory..."
	mkdir -p dist/release
	cp dist/screaming-penguin.img dist/release/screaming-penguin-v1.0.0.img
	cp dist/screaming-penguin.iso dist/release/screaming-penguin-v1.0.0.iso
	cp dist/debian-rootfs-bookworm-amd64.tar.gz dist/release/debian-rootfs-bookworm-amd64-v1.0.0.tar.gz
	mkdir -p dist/release/example-configs
	cp -r config/examples/*.yml dist/release/example-configs/
	cd dist/release && find . -type f -maxdepth 1 -print0 | xargs -0 sha256sum > SHA256SUMS
