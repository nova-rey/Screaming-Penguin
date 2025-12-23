import os
import shutil
import subprocess
from pathlib import Path
from shlex import quote

import pytest

MIN_INITRD_SIZE_BYTES = 1 * 1024 * 1024
REQUIRED_TOOLS = ("gzip", "cpio")
HAS_REQUIRED_TOOLS = all(shutil.which(tool) for tool in REQUIRED_TOOLS)

RUNTIME_LIB_ENTRIES = (
    "init",
    "runtime/lib/rescue_mode.sh",
    "runtime/lib/disk_layout.sh",
    "runtime/lib/disk_execute.sh",
    "runtime/lib/rootfs_deploy.sh",
    "runtime/lib/bootloader.sh",
    "runtime/lib/config_discovery.sh",
)

TEST_KERNEL_VERSION = "test-kernel"
FAT_MODULE_PATHS = (
    Path("kernel/fs/fat/fat.ko"),
    Path("kernel/fs/fat/vfat.ko"),
    Path("kernel/fs/nls/nls_cp437.ko"),
    Path("kernel/fs/nls/nls_iso8859-1.ko"),
)


def _prepare_kernel_environment(kernel_version: str = TEST_KERNEL_VERSION):
    kernel_dir = Path("build/runtime")
    kernel_dir.mkdir(parents=True, exist_ok=True)
    kernel_image = kernel_dir / "vmlinuz"
    kernel_image.write_bytes(b"FAKE-KERNEL")

    modules_root = Path("build/runtime-chroot/lib/modules")
    modules_root.mkdir(parents=True, exist_ok=True)
    modules_src = modules_root / kernel_version
    if modules_src.exists():
        shutil.rmtree(modules_src)
    modules_src.mkdir(parents=True, exist_ok=True)
    (modules_src / "dummy").write_text("module")

    for module_path in FAT_MODULE_PATHS:
        target_path = modules_src / module_path
        target_path.parent.mkdir(parents=True, exist_ok=True)
        target_path.write_text(f"stub {module_path.name}")

    env = os.environ.copy()
    env.update(
        {
            "SP_INSTALLER_KERNEL_IMAGE": str(kernel_image),
            "SP_INSTALLER_KERNEL_VERSION": kernel_version,
            "SP_INSTALLER_MODULES_ROOT": str(modules_root),
        }
    )

    return env


def _run_installer_initrd_build(env):
    try:
        subprocess.run(
            ["bash", "tools/build_installer_initramfs.sh"],
            check=True,
            capture_output=True,
            text=True,
            env=env,
        )
    except subprocess.CalledProcessError as exc:
        stdout = exc.stdout.rstrip("\n") if exc.stdout else "<no stdout>"
        stderr = exc.stderr.rstrip("\n") if exc.stderr else "<no stderr>"
        pytest.fail(
            "tools/build_installer_initramfs.sh failed "
            f"(exit {exc.returncode}).\nstdout:\n{stdout}\nstderr:\n{stderr}"
        )

    return Path("dist") / "initrd-installer.img"


def _list_initrd_entries(initrd_path: Path):
    list_cmd = f"gzip -cd {quote(str(initrd_path))} | cpio -t -H newc"
    proc = subprocess.run(
        ["bash", "-lc", list_cmd],
        check=True,
        capture_output=True,
        text=True,
    )

    return {
        line.strip().lstrip("./") for line in proc.stdout.splitlines() if line.strip()
    }


@pytest.mark.skipif(
    not HAS_REQUIRED_TOOLS,
    reason="gzip/cpio required for initrd validation",
)
def test_installer_initrd_contains_runtime_payload() -> None:
    env = _prepare_kernel_environment()
    initrd_path = _run_installer_initrd_build(env)
    assert initrd_path.exists(), "initrd-installer.img should exist after the build"

    assert (
        initrd_path.stat().st_size >= MIN_INITRD_SIZE_BYTES
    ), f"initrd-installer.img is too small ({initrd_path.stat().st_size} bytes)"

    entries = _list_initrd_entries(initrd_path)

    assert "bin/busybox" in entries
    for required in RUNTIME_LIB_ENTRIES:
        assert required in entries

    init_script_path = Path("build/installer-initramfs/init")
    init_content = init_script_path.read_text(encoding="utf-8")
    assert "sp_load_filesystem_modules" in init_content
    assert "for module in fat vfat nls_cp437 nls_iso8859-1" in init_content


@pytest.mark.skipif(
    not HAS_REQUIRED_TOOLS,
    reason="gzip/cpio required for initrd validation",
)
def test_installer_initrd_includes_vfat_support() -> None:
    env = _prepare_kernel_environment()
    initrd_path = _run_installer_initrd_build(env)

    entries = _list_initrd_entries(initrd_path)
    module_entries = {
        f"lib/modules/{TEST_KERNEL_VERSION}/{module.as_posix()}"
        for module in FAT_MODULE_PATHS
    }
    for module_entry in module_entries:
        assert module_entry in entries

    init_script_path = Path("build/installer-initramfs/init")
    init_content = init_script_path.read_text(encoding="utf-8")
    assert "sp_try_load_fat_stack" in init_content
    assert 'sp_log "fat-stack: probing modules (${modules})"' in init_content
