# Screaming Penguin - Makefile (Phase 3)
# Provides image build and cleanup targets.

.PHONY: iso clean

iso:
	@echo "[MAKE] Building Screaming Penguin installer image…"
	sh tools/make_installer_iso.sh

clean:
	@echo "[MAKE] Cleaning build and dist artifacts…"
	rm -rf build/*
	rm -rf dist/*
