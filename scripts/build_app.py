#!/usr/bin/env python3
"""Assemble a portable HighDock app bundle from the pinned Swift package."""

import argparse
import os
from pathlib import Path
import plistlib
import shutil
import tempfile

from release_support import ROOT, SPARKLE, run


def build_app(destination, *, version=None, build=None, universal=False, updates=False, log=None):
    destination = Path(destination).resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    architectures = ["arm64", "x86_64"] if universal else [None]
    binaries = []
    for architecture in architectures:
        arguments = ["swift", "build", "-c", "release", "--disable-sandbox", "--force-resolved-versions", "--product", "HighDock"]
        if architecture:
            arguments += ["--arch", architecture]
        run(*arguments, log=log)
        directory = Path(run(*arguments, "--show-bin-path", capture=True))
        binaries.append(directory / "HighDock")
    with tempfile.TemporaryDirectory(prefix="highdock-bundle-", dir=destination.parent) as staging:
        app = Path(staging) / "HighDock.app"
        macos = app / "Contents/MacOS"
        resources = app / "Contents/Resources"
        frameworks = app / "Contents/Frameworks"
        for directory in (macos, resources, frameworks):
            directory.mkdir(parents=True)
        executable = macos / "HighDock"
        if universal:
            run("lipo", "-create", *(str(path) for path in binaries), "-output", str(executable))
        else:
            shutil.copy2(binaries[0], executable)
        executable.chmod(0o755)
        shutil.copy2(ROOT / "Resources/HighDock.icns", resources)
        shutil.copy2(SPARKLE / "LICENSE", resources / "Sparkle-LICENSE.txt")
        framework = SPARKLE / "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
        shutil.copytree(framework, frameworks / "Sparkle.framework", symlinks=True)
        with (ROOT / "Resources/Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        if version is not None:
            info["CFBundleShortVersionString"] = version
        if build is not None:
            info["CFBundleVersion"] = str(build)
        info["HighDockUpdatesEnabled"] = updates
        with (app / "Contents/Info.plist").open("wb") as stream:
            plistlib.dump(info, stream, sort_keys=False)
        run("codesign", "--force", "--sign", "-", str(app))
        if destination.exists():
            os.replace(destination, Path(staging) / "previous.app")
        os.replace(app, destination)
    print(f"Built {destination}", flush=True)
    return destination


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--universal", action="store_true")
    arguments = parser.parse_args()
    build_app(ROOT / "build/HighDock.app", universal=arguments.universal)
