#!/usr/bin/env python3
"""Build the native app using Apple's toolchain and the Python standard library."""
import argparse
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / ".build"
DIST = ROOT / "dist"


def run(arguments):
    subprocess.run([str(value) for value in arguments], check=True)


def sdk_path(explicit):
    if explicit:
        return Path(explicit).resolve()
    # Prefer a CLT SDK matching the host when an older CLT installation has leftovers.
    sdk_root = Path("/Library/Developer/CommandLineTools/SDKs")
    major = platform.mac_ver()[0].split(".")[0]
    candidates = list(sdk_root.glob(f"MacOSX{major}.*.sdk"))
    if candidates:
        return max(candidates, key=lambda value: tuple(int(n) for n in re.findall(r"\d+", value.name)))
    return Path(subprocess.check_output(["/usr/bin/xcrun", "--show-sdk-path"], text=True).strip())


def overlay():
    # Hide a stale duplicate module map only for this compiler invocation.
    # Never edit or delete files in the system developer tools.
    directory = Path("/Library/Developer/CommandLineTools/usr/include/swift")
    roots = []
    if (directory / "module.modulemap").exists() and (directory / "bridging.modulemap").exists():
        empty = BUILD / "empty.modulemap"
        empty.write_text("// Stale duplicate module map hidden during this build.\n")
        roots.append({"type": "file", "name": str(directory / "module.modulemap"), "external-contents": str(empty)})
    result = BUILD / "compiler-overlay.json"
    result.write_text(json.dumps({"version": 0, "roots": roots}))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--test", action="store_true", help="Run fixture tests; does not change live proxy settings")
    parser.add_argument("--preview", action="store_true", help="Render sample UI states with fictional node labels")
    parser.add_argument("--sdk", help="Override the SDK path")
    args = parser.parse_args()
    if platform.system() != "Darwin":
        parser.error("This native AppKit application must be built on macOS.")
    BUILD.mkdir(exist_ok=True)
    DIST.mkdir(exist_ok=True)
    version = (ROOT / "VERSION").read_text().strip()
    executable = BUILD / "MihomoController"
    compiler = subprocess.check_output(["/usr/bin/xcrun", "--find", "swiftc"], text=True).strip()
    run([compiler, "-swift-version", "5", "-O", "-sdk", sdk_path(args.sdk),
         "-target", f"{platform.machine()}-apple-macosx14.0",
         "-vfsoverlay", overlay(), "-module-cache-path", BUILD / "module-cache",
         "-file-prefix-map", f"{ROOT}=.", "-framework", "Cocoa", "-framework", "SystemConfiguration",
         ROOT / "Sources/Core.swift", ROOT / "Tests/EngineTests.swift", ROOT / "Sources/main.swift",
         "-o", executable])
    if args.test:
        run([executable, "--self-test"])
    if args.preview:
        images = ROOT / "docs/images"
        images.mkdir(parents=True, exist_ok=True)
        run([executable, "--render-preview", images / "enabled.png"])
        run([executable, "--render-preview", images / "stopped.png", "--stopped"])
    app = DIST / "Mihomo 控制器.app"
    if app.exists():
        shutil.rmtree(app)
    contents = app / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    (contents / "Resources").mkdir()
    shutil.copy2(executable, contents / "MacOS/MihomoController")
    shutil.copy2(ROOT / "Assets/AppIcon.icns", contents / "Resources/AppIcon.icns")
    info = {
        "CFBundleExecutable": "MihomoController",
        "CFBundleIdentifier": "io.github.zxhdaniel.mihomo-controller",
        "CFBundleName": "Mihomo 控制器", "CFBundleDisplayName": "Mihomo 控制器",
        "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version,
        "CFBundleVersion": version, "CFBundleIconFile": "AppIcon",
        "LSMinimumSystemVersion": "14.0", "NSHighResolutionCapable": True,
        "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True},
    }
    (contents / "Info.plist").write_bytes(plistlib.dumps(info))
    run(["/usr/bin/codesign", "--force", "--sign", "-", app])
    run(["/usr/bin/codesign", "--verify", "--strict", "--deep", app])
    archive = DIST / f"MihomoController-{version}-macos-{platform.machine()}.zip"
    archive.unlink(missing_ok=True)
    run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, archive])
    print(f"Built: {archive.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
