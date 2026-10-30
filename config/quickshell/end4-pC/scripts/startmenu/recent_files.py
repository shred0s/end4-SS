#!/usr/bin/env python3
"""Lists recently opened files from recently-used.xbel as JSON for the start menu.

Usage: recent_files.py [LIMIT]
Each entry: {path, name, mime, time}, newest first; files that are gone are left out.
"""
import json
import os
import sys
import xml.etree.ElementTree as ET
from datetime import datetime
from urllib.parse import unquote, urlparse

MIME_NS = "{http://www.freedesktop.org/standards/shared-mime-info}"


def xbel_path():
    data_home = os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share"))
    return os.path.join(data_home, "recently-used.xbel")


def timestamp(value):
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except (AttributeError, ValueError):
        return 0


def main():
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 6
    try:
        root = ET.parse(xbel_path()).getroot()
    except (OSError, ET.ParseError):
        print("[]")
        return

    entries = []
    for bookmark in root.iter("bookmark"):
        url = urlparse(bookmark.get("href", ""))
        if url.scheme != "file":
            continue
        path = unquote(url.path)
        time = max(timestamp(bookmark.get(key)) for key in ("added", "modified", "visited"))
        mime = bookmark.find(f".//{MIME_NS}mime-type")
        entries.append((time, path, mime.get("type", "") if mime is not None else ""))

    entries.sort(reverse=True)
    seen = set()
    result = []
    for time, path, mime in entries:
        if path in seen or not os.path.isfile(path):
            continue
        seen.add(path)
        result.append({"path": path, "name": os.path.basename(path), "mime": mime, "time": int(time)})
        if len(result) >= limit:
            break
    print(json.dumps(result))


if __name__ == "__main__":
    main()
