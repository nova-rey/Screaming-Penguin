"""Tests for the Phase 11 rootfs deployment helpers."""

from __future__ import annotations

import os
import shlex
import subprocess
import textwrap
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
ROOTFS_LIB = REPO_ROOT / "installer/runtime/lib/rootfs_deploy.sh"


def _write_config(tmp_dir: Path, tarball_path: Path) -> Path:
    config_path = tmp_dir / "installer-config.yml"
    contents = (
        textwrap.dedent(
            f"""
        version: 0.1

        installer:
          write_gate: true
          rootfs:
            tarball: "{tarball_path}"
            target_mount: "/mnt/target"
            hostname: "penguin-test"
            timezone: "Etc/UTC"
            locale: "en_US.UTF-8 UTF-8"
            username: "penguin"
            password_hash: "$6$replace-with-real-hash"
            ssh_authorized_keys:
              - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA...replace..."
        """
        ).strip()
        + "\n"
    )
    config_path.write_text(contents)
    return config_path


def _run_shell_script(tmp_dir: Path, script: str) -> subprocess.CompletedProcess:
    env = os.environ.copy()
    env["SP_LOG_DEVICE"] = str(tmp_dir / "rootfs.log")
    env["PATH"] = f"/tmp:{env.get('PATH', '')}"
    return subprocess.run(
        ["/bin/bash", "-c", script],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def _script_preamble(log_path: Path) -> str:
    return textwrap.dedent(
        """
        sp_trim() { printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }
        """
    )


def test_rootfs_deploy_extracts_tarball(tmp_path: Path) -> None:
    rootfs_source = tmp_path / "src"
    (rootfs_source / "etc").mkdir(parents=True)
    (rootfs_source / "etc" / "payload.txt").write_text("rootfs-content")

    tarball_path = tmp_path / "rootfs.tar.gz"
    subprocess.run(
        ["tar", "-C", str(rootfs_source), "-czf", str(tarball_path), "."], check=True
    )

    target_dir = tmp_path / "target"
    target_dir.mkdir()
    config_path = _write_config(tmp_path, tarball_path)
    preamble = _script_preamble(tmp_path / "rootfs.log")

    script = textwrap.dedent(
        f"""
        {preamble}
        SP_CONFIG_PATH={shlex.quote(str(config_path))}
        SP_ROOTFS_TARGET_DIR_OVERRIDE={shlex.quote(str(target_dir))}
        SP_SKIP_CHROOT_CONFIG=1
        SP_SKIP_ROOTFS_DEPLOY=0
        . "{ROOTFS_LIB}"
        sp_rootfs_deploy_and_configure
        """
    )

    result = _run_shell_script(tmp_path, script)
    assert result.returncode == 0, result.stderr
    assert (target_dir / "etc" / "payload.txt").read_text() == "rootfs-content"


def test_rootfs_deploy_respects_skip_flag(tmp_path: Path) -> None:
    rootfs_source = tmp_path / "src"
    (rootfs_source / "etc").mkdir(parents=True)
    (rootfs_source / "etc" / "payload.txt").write_text("rootfs-content")

    tarball_path = tmp_path / "rootfs.tar.gz"
    subprocess.run(
        ["tar", "-C", str(rootfs_source), "-czf", str(tarball_path), "."], check=True
    )

    target_dir = tmp_path / "target"
    target_dir.mkdir()
    config_path = _write_config(tmp_path, tarball_path)
    preamble = _script_preamble(tmp_path / "rootfs.log")

    script = textwrap.dedent(
        f"""
        {preamble}
        SP_CONFIG_PATH={shlex.quote(str(config_path))}
        SP_ROOTFS_TARGET_DIR_OVERRIDE={shlex.quote(str(target_dir))}
        SP_SKIP_CHROOT_CONFIG=1
        SP_SKIP_ROOTFS_DEPLOY=1
        . "{ROOTFS_LIB}"
        sp_rootfs_deploy_and_configure
        """
    )

    result = _run_shell_script(tmp_path, script)
    assert result.returncode == 0, result.stderr
    assert not (target_dir / "etc" / "payload.txt").exists()


def test_rootfs_configuration_writes_hostname_and_timezone(tmp_path: Path) -> None:
    target_dir = tmp_path / "target"
    (target_dir / "etc").mkdir(parents=True)
    (target_dir / "usr/share/zoneinfo/Etc").mkdir(parents=True)
    zonefile = target_dir / "usr/share/zoneinfo/Etc/UTC"
    zonefile.write_text("zoneinfo-data")

    locale_file = target_dir / "etc/locale.gen"
    locale_file.write_text("# en_US.UTF-8 UTF-8\n")

    preamble = _script_preamble(tmp_path / "rootfs.log")
    script = textwrap.dedent(
        f"""
        {preamble}
        SP_ROOTFS_TARGET_DIR={shlex.quote(str(target_dir))}
        SP_ROOTFS_HOSTNAME="penguin-host"
        SP_ROOTFS_TIMEZONE="Etc/UTC"
        SP_ROOTFS_LOCALE="en_US.UTF-8 UTF-8"
        . "{ROOTFS_LIB}"
        sp_rootfs_write_hostname
        sp_rootfs_configure_timezone
        sp_rootfs_ensure_locale_entry
        """
    )

    result = _run_shell_script(tmp_path, script)
    assert result.returncode == 0, result.stderr
    assert (target_dir / "etc" / "hostname").read_text().strip() == "penguin-host"
    hosts = (target_dir / "etc" / "hosts").read_text()
    assert "127.0.1.1 penguin-host" in hosts
    assert (target_dir / "etc" / "timezone").read_text().strip() == "Etc/UTC"
    localtime = target_dir / "etc" / "localtime"
    assert localtime.is_symlink()
    assert localtime.resolve() == zonefile.resolve()
    assert "en_US.UTF-8 UTF-8" in locale_file.read_text()
