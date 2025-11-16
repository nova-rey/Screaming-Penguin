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

# Phase 7 — Release Packaging
# Assemble installer ISO, rootfs tarball, example configs, and checksums into dist/release/

dist-release: iso rootfs
	@echo "[DIST] Assembling v1.0.0 release directory..."
	mkdir -p dist/release
	cp dist/screaming-penguin.img dist/release/screaming-penguin-v1.0.0.img
	cp dist/debian-rootfs-bookworm-amd64.tar.gz dist/release/debian-rootfs-bookworm-amd64-v1.0.0.tar.gz
	
	# Example configuration bundle
	mkdir -p dist/release/example-configs
	cp -r config/examples/*.yml dist/release/example-configs/
	
	# Generate SHA256 checksums
	cd dist/release && find . -maxdepth 1 -type f ! -name 'SHA256SUMS' -exec sha256sum {} + > SHA256SUMS
	
	@echo "[DIST] Release bundle assembled under dist/release/"
