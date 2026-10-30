#!/usr/bin/env python3
"""List and manage the desktop trash for the dock's trash viewer.

Works on the freedesktop.org trash folders directly (the home trash plus the
.Trash-$UID / .Trash/$UID folders on other mounted drives), the same ones Dolphin,
Nautilus and `gio trash` use. gvfsd-trash is skipped on purpose: its index goes
stale when an item is restored and a same-named file is trashed again.

Usage:
  trash.py list            print every trashed item as a JSON array, newest first
  trash.py restore ID...   move items back to where they were trashed from
  trash.py delete ID...    permanently delete items
  trash.py empty           permanently delete everything in the trash
  trash.py watch           print a line whenever any trash folder changes

An ID is the item's .trashinfo path, as given by `list`. Actions print
{"done": [...], "errors": [{"id", "message"}]} as JSON.
"""
import configparser
import json
import mimetypes
import os
import re
import shutil
import stat
import sys
from urllib.parse import unquote

UID = os.getuid()
# Walking huge folders for their size would stall the viewer, so stop counting here.
MAX_WALK_ENTRIES = 20000
PSEUDO_MOUNT_ROOTS = ("/proc", "/sys", "/dev", "/run/user", "/tmp", "/boot", "/efi")


def home_trash():
    data_home = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return os.path.join(data_home, "Trash")


def mount_points():
    with open("/proc/self/mounts") as mounts:
        for line in mounts:
            # Spaces and tabs in mount points are octal-escaped in /proc/mounts.
            point = re.sub(r"\\([0-7]{3})", lambda m: chr(int(m.group(1), 8)), line.split()[1])
            if point != "/" and not point.startswith(PSEUDO_MOUNT_ROOTS):
                yield point


def trash_dirs():
    """Yield (trash dir, top dir for relative paths or None) for every trash that exists."""
    yield home_trash(), None
    seen = {os.path.realpath(home_trash())}
    for top in mount_points():
        shared = os.path.join(top, ".Trash")
        candidates = [os.path.join(top, f".Trash-{UID}")]
        # The spec only trusts an admin-made .Trash when it's a real, sticky directory.
        try:
            info = os.lstat(shared)
            if stat.S_ISDIR(info.st_mode) and info.st_mode & stat.S_ISVTX:
                candidates.insert(0, os.path.join(shared, str(UID)))
        except OSError:
            pass
        for trash in candidates:
            real = os.path.realpath(trash)
            if real not in seen and os.path.isdir(os.path.join(trash, "info")):
                seen.add(real)
                yield trash, top


def folder_stats(path):
    """Return (total bytes, direct child count, exact) for a folder."""
    try:
        children = len(os.listdir(path))
    except OSError:
        return 0, 0, False
    total = 0
    seen = 0
    for root, _dirs, files in os.walk(path):
        for name in files:
            seen += 1
            if seen > MAX_WALK_ENTRIES:
                return total, children, False
            try:
                total += os.lstat(os.path.join(root, name)).st_size
            except OSError:
                pass
    return total, children, True


def icon_names(name, is_dir):
    if is_dir:
        return ["inode-directory", "folder"]
    mime, _ = mimetypes.guess_type(name, strict=False)
    if not mime:
        return ["text-x-generic", "unknown"]
    major = mime.split("/")[0]
    generic = {"application": "application-x-generic"}.get(major, f"{major}-x-generic")
    return [mime.replace("/", "-"), generic, "text-x-generic"]


def read_trashinfo(info_path, top):
    parser = configparser.ConfigParser(interpolation=None)
    parser.optionxform = str
    with open(info_path, encoding="utf-8", errors="replace") as handle:
        parser.read_file(handle)
    section = parser["Trash Info"]
    orig_path = unquote(section.get("Path", ""))
    if orig_path and top and not os.path.isabs(orig_path):
        orig_path = os.path.join(top, orig_path)
    return orig_path, section.get("DeletionDate", "")


def item_paths(info_path):
    """Return (trash dir, stored file path) for a .trashinfo, rejecting anything else."""
    info_dir = os.path.dirname(os.path.abspath(info_path))
    trash = os.path.dirname(info_dir)
    known = {os.path.realpath(dir_) for dir_, _top in trash_dirs()}
    if (not info_path.endswith(".trashinfo") or os.path.basename(info_dir) != "info"
            or os.path.realpath(trash) not in known):
        raise ValueError("Not an item in a trash folder")
    name = os.path.basename(info_path)[: -len(".trashinfo")]
    return trash, os.path.join(trash, "files", name)


def list_items():
    items = []
    for trash, top in trash_dirs():
        info_dir = os.path.join(trash, "info")
        try:
            entries = os.listdir(info_dir)
        except OSError:
            continue
        for entry in entries:
            if not entry.endswith(".trashinfo"):
                continue
            info_path = os.path.join(info_dir, entry)
            name = entry[: -len(".trashinfo")]
            path = os.path.join(trash, "files", name)
            try:
                file_stat = os.lstat(path)
                orig_path, deletion_date = read_trashinfo(info_path, top)
            except (OSError, KeyError, configparser.Error):
                continue  # Orphaned or unreadable entry
            is_dir = stat.S_ISDIR(file_stat.st_mode)
            size, child_count, size_exact = file_stat.st_size, 0, True
            if is_dir:
                size, child_count, size_exact = folder_stats(path)
            display_name = os.path.basename(orig_path) if orig_path else name
            items.append({
                "id": info_path,
                "name": display_name,
                "path": path,
                "origPath": orig_path,
                "origDir": os.path.dirname(orig_path),
                "deletionDate": deletion_date,
                "size": size,
                "sizeExact": size_exact,
                "isDir": is_dir,
                "childCount": child_count,
                "icons": icon_names(display_name, is_dir),
            })
    items.sort(key=lambda item: item["deletionDate"], reverse=True)
    return items


def free_destination(path):
    """Pick a path next to `path` that doesn't exist yet, so restoring never overwrites."""
    if not os.path.lexists(path):
        return path
    folder, name = os.path.split(path)
    stem, ext = os.path.splitext(name)
    for n in range(1, 1000):
        suffix = " (restored)" if n == 1 else f" (restored {n})"
        candidate = os.path.join(folder, f"{stem}{suffix}{ext}")
        if not os.path.lexists(candidate):
            return candidate
    raise FileExistsError(path)


def restore(info_path):
    trash, stored = item_paths(info_path)
    top = next((top for dir_, top in trash_dirs() if os.path.realpath(dir_) == os.path.realpath(trash)), None)
    orig_path, _date = read_trashinfo(info_path, top)
    if not orig_path:
        raise ValueError("Original location is unknown")
    destination = free_destination(orig_path)
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    shutil.move(stored, destination)
    os.remove(info_path)
    return destination


def delete(info_path):
    _trash, stored = item_paths(info_path)
    if os.path.isdir(stored) and not os.path.islink(stored):
        shutil.rmtree(stored)
    elif os.path.lexists(stored):
        os.remove(stored)
    os.remove(info_path)
    return info_path


def run_action(action, ids):
    done, errors = [], []
    for item_id in ids:
        try:
            done.append(action(item_id))
        except (OSError, ValueError, KeyError, configparser.Error) as error:
            message = error.strerror if isinstance(error, OSError) and error.strerror else str(error)
            errors.append({"id": item_id, "message": message})
    return {"done": done, "errors": errors}


def watch():
    home = home_trash()
    for sub in ("info", "files"):
        os.makedirs(os.path.join(home, sub), mode=0o700, exist_ok=True)
    args = ["gio", "monitor"]
    for trash, _top in trash_dirs():
        args += ["-d", os.path.join(trash, "info")]
    sys.stdout.flush()
    os.execvp("gio", args)


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    command, args = argv[1], argv[2:]
    if command == "list":
        result = list_items()
    elif command == "restore":
        result = run_action(restore, args)
    elif command == "delete":
        result = run_action(delete, args)
    elif command == "empty":
        result = run_action(delete, [item["id"] for item in list_items()])
    elif command == "watch":
        watch()
        return 0
    else:
        print(__doc__, file=sys.stderr)
        return 2
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
