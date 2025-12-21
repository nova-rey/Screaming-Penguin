import os
import subprocess
from pathlib import Path


def test_local_runtime_lib_has_priority(tmp_path: Path) -> None:
    installer_root = tmp_path / "installer-initramfs"
    local_runtime_lib = installer_root / "runtime" / "lib"
    parent_runtime_lib = tmp_path / "runtime" / "lib"

    local_runtime_lib.mkdir(parents=True)
    parent_runtime_lib.mkdir(parents=True)

    local_config = local_runtime_lib / "config_discovery.sh"
    parent_config = parent_runtime_lib / "config_discovery.sh"
    local_config.write_text("#!/bin/sh\nprintf 'LOCAL_LIB\\n'\n")
    parent_config.write_text("#!/bin/sh\nprintf 'PARENT_LIB\\n'\n")

    log_device = tmp_path / "sp.log"
    log_device.write_text("")

    repo_root = Path(__file__).resolve().parents[2]
    env = os.environ.copy()
    env.update(
        {
            "SP_SKIP_INIT_MAIN": "1",
            "SP_INIT_SCRIPT_PATH": str(installer_root / "init"),
            "SP_LOG_DEVICE": str(log_device),
        }
    )

    result = subprocess.run(
        ["bash", "-c", ". build/installer-initramfs/init"],
        cwd=str(repo_root),
        env=env,
        capture_output=True,
        text=True,
        check=True,
    )

    assert "LOCAL_LIB" in result.stdout
    assert "PARENT_LIB" not in result.stdout
