import os
import shutil
import subprocess
from pathlib import Path

import pytest


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


def _run_installer_initramfs_build(env):
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
