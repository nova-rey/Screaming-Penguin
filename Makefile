# Screaming Penguin - Makefile

BUILD_DIR := build
RUNTIME_DIR := $(BUILD_DIR)/runtime
CI_SMOKE_PYTEST_TIMEOUT_SECONDS ?= 600
CI_SMOKE_FULL_INSTALLER ?= 0

.PHONY: img iso rootfs clean qemu-acceptance runtime installer-runtime ci-smoke ci-iso
img: $(RUNTIME_DIR)/.installer-runtime-built
	@echo "[MAKE] Building Screaming Penguin installer image…"
	bash tools/make_installer_img.sh

iso:
	@echo "[MAKE] ISO builds are disabled in this repository; see the Ouroboros side project for hybrid ISO support." >&2
	@false

installer-runtime:
	@rm -f $(RUNTIME_DIR)/.installer-runtime-built
	@$(MAKE) $(RUNTIME_DIR)/.installer-runtime-built

$(RUNTIME_DIR)/.installer-runtime-built:
	@echo "[MAKE] Building installer runtime artifacts…"
	bash tools/build_runtime.sh
	bash tools/build_installer_initramfs.sh
	mkdir -p dist
	cp "$(RUNTIME_DIR)/vmlinuz" dist/vmlinuz-installer
	mkdir -p $(BUILD_DIR)
	cp -f dist/initrd-installer.img $(BUILD_DIR)/initrd-installer.img
	touch "$@"

runtime: installer-runtime

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

ci-smoke:
	@echo "[MAKE] Running CI smoke suite..."
	bash tools/ci_smoke.sh

ci-iso:
	@echo "[MAKE] CI ISO suite disabled; ISO builds are no longer part of the default workflow (Ouroboros handles them)." >&2
	@false

# Phase 7 — Release Packaging
# Assemble installer ISO, rootfs tarball, example configs, and checksums into dist/release/

dist-release: img rootfs
	@echo "[DIST] Assembling v1.0.0 release directory..."
	mkdir -p dist/release
	cp dist/screaming-penguin.img dist/release/screaming-penguin-v1.0.0.img
	cp dist/debian-rootfs-bookworm-amd64.tar.gz dist/release/debian-rootfs-bookworm-amd64-v1.0.0.tar.gz
	mkdir -p dist/release/example-configs
	cp -r config/examples/*.yml dist/release/example-configs/
	cd dist/release && find . -type f -maxdepth 1 -print0 | xargs -0 sha256sum > SHA256SUMS
