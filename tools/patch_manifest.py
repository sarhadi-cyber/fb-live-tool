#!/usr/bin/env python3
"""Patch the flutter-create Android project for FB Live Tool.

Run in the GitHub Actions workflow AFTER `flutter create .`:
  python3 tools/patch_manifest.py

What it does (idempotent, safe to run twice):
  1. android/app/src/main/AndroidManifest.xml:
     adds INTERNET, ACCESS_NETWORK_STATE, READ_MEDIA_VIDEO,
     READ_EXTERNAL_STORAGE (for older Android), FOREGROUND_SERVICE.
  2. android/app/build.gradle.kts (or build.gradle):
     sets minSdk to 26, because ffmpeg_kit_extended needs Android API 26+.
"""
import re
import sys
from pathlib import Path

PERMS = [
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.READ_MEDIA_VIDEO",
    "android.permission.READ_EXTERNAL_STORAGE",
    "android.permission.FOREGROUND_SERVICE",
]


def patch_manifest(path: Path):
    text = path.read_text()
    if "android.permission.INTERNET" in text:
        print(f"Manifest already patched: {path}")
        return
    perms_xml = "".join(f'    <uses-permission android:name="{p}"/>\n' for p in PERMS)
    if "<application" in text:
        text = text.replace("<application", perms_xml + "    <application", 1)
    else:
        text = perms_xml + text
    path.write_text(text)
    print(f"Patched manifest: {path}")


def patch_gradle(path: Path):
    text = path.read_text()
    orig = text
    # build.gradle.kts style: minSdk = flutter.minSdkVersion  /  minSdk = 21
    text = re.sub(r"minSdk\s*=\s*[^\n]+", "minSdk = 26", text, count=1)
    # build.gradle style: minSdkVersion 21  /  minSdkVersion flutter.minSdkVersion
    text = re.sub(r"minSdkVersion\s+[^\n]+", "minSdkVersion 26", text, count=1)
    if text != orig:
        path.write_text(text)
        print(f"Patched gradle (minSdk 26): {path}")
    else:
        print(f"WARNING: no minSdk found in {path} - check it manually")


def main():
    manifest = Path("android/app/src/main/AndroidManifest.xml")
    if manifest.exists():
        patch_manifest(manifest)
    else:
        print(f"ERROR: manifest not found: {manifest}", file=sys.stderr)
        sys.exit(1)
    for gradle in [
        Path("android/app/build.gradle.kts"),
        Path("android/app/build.gradle"),
    ]:
        if gradle.exists():
            patch_gradle(gradle)
            break
    else:
        print("WARNING: no android gradle file found")


if __name__ == "__main__":
    main()
