#!/usr/bin/env python3
"""Create a per-user launch agent for an already configured Mihomo installation."""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import os


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, help="Path to an existing Mihomo executable")
    parser.add_argument("--config-dir", type=Path, default=Path.home() / ".config/mihomo")
    parser.add_argument("--load", action="store_true", help="Also load the agent now")
    args = parser.parse_args()
    binary = args.binary or Path(shutil.which("mihomo") or Path.home() / ".local/bin/mihomo")
    binary = binary.expanduser().resolve()
    directory = args.config_dir.expanduser().resolve()
    if not binary.is_file() or not os.access(binary, os.X_OK):
        parser.error("Mihomo executable not found; install it first or pass --binary.")
    if not (directory / "config.yaml").is_file():
        parser.error("Configure your own config.yaml before creating the service.")
    target = Path.home() / "Library/LaunchAgents/com.mihomo.proxy.plist"
    if target.exists():
        parser.error("Launch agent already exists; it has not been overwritten.")
    data = {
        "Label": "com.mihomo.proxy", "ProgramArguments": [str(binary), "-d", str(directory)],
        "RunAtLoad": True, "KeepAlive": True,
        "StandardOutPath": str(directory / "mihomo.stdout.log"),
        "StandardErrorPath": str(directory / "mihomo.stderr.log"),
    }
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("xb") as stream:
        stream.write(plistlib.dumps(data))
    target.chmod(0o600)
    if args.load:
        subprocess.run(["/bin/launchctl", "bootstrap", f"gui/{os.getuid()}", str(target)], check=True)
    print("Launch agent created. Its paths are stored locally, never in the repository.")


if __name__ == "__main__":
    main()
