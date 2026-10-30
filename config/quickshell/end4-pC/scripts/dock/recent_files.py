#!/usr/bin/env python3
"""Lists the newest entries of a folder as JSON for the dock's Downloads fan.

Usage: recent_files.py [DIR] [LIMIT]
Each entry: {path, name, dir, mtime, size, mime, icon, image}. Hidden files and
unfinished downloads (.part, .crdownload, ...) are left out.
"""
import json
import mimetypes
import os
import subprocess
import sys

PARTIAL = (".part", ".crdownload", ".download", ".partial", ".tmp")
# Icon names from the freedesktop icon naming spec, by mime prefix
GENERIC = {
    "image/": "image-x-generic",
    "video/": "video-x-generic",
    "audio/": "audio-x-generic",
    "text/": "text-x-generic",
    "font/": "font-x-generic",
}
ARCHIVES = {"zip", "x-tar", "gzip", "x-7z-compressed", "x-rar", "vnd.rar", "x-xz", "x-bzip2", "zstd", "x-zstd"}


def downloads_dir():
    try:
        out = subprocess.run(["xdg-user-dir", "DOWNLOAD"], capture_output=True, text=True, timeout=2).stdout.strip()
        if out and os.path.isdir(out):
            return out
    except (OSError, subprocess.SubprocessError):
        pass
    return os.path.expanduser("~/Downloads")


def icon_for(mime, is_dir):
    if is_dir:
        return "folder"
    if not mime:
        return "unknown"
    major, _, minor = mime.partition("/")
    if major == "application" and minor in ARCHIVES:
        return "package-x-generic"
    return mime.replace("/", "-")


def generic_icon(mime, is_dir):
    if is_dir:
        return "folder"
    for prefix, icon in GENERIC.items():
        if mime and mime.startswith(prefix):
            return icon
    return "application-x-generic"


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else downloads_dir()
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 60
    entries = []
    try:
        with os.scandir(folder) as it:
            for entry in it:
                if entry.name.startswith(".") or entry.name.lower().endswith(PARTIAL):
                    continue
                try:
                    info = entry.stat()
                except OSError:
                    continue
                entries.append((info.st_mtime, entry, info))
    except OSError:
        pass
    entries.sort(key=lambda item: item[0], reverse=True)
    result = []
    for mtime, entry, info in entries[:limit]:
        is_dir = entry.is_dir()
        mime = None if is_dir else mimetypes.guess_type(entry.name)[0]
        result.append({
            "path": entry.path,
            "name": entry.name,
            "dir": is_dir,
            "mtime": mtime,
            "size": 0 if is_dir else info.st_size,
            "mime": mime or "",
            "icon": icon_for(mime, is_dir),
            "fallback": generic_icon(mime, is_dir),
            "image": bool(mime and mime.startswith("image/") and mime != "image/svg+xml" and info.st_size < 40_000_000),
        })
    print(json.dumps({"folder": folder, "items": result}))


if __name__ == "__main__":
    main()
