#!/usr/bin/env python3
"""The clip library: video files named <id>.<ext> in one folder, their metadata in an SQLite database.

Usage: clips_db.py --library <dir> [--cache <dir>] <command> ...

  index                               Adopt new files, refresh metadata and thumbnails, print the library as JSON
  add <file> [--game G --appid A --class C]
                                      Move a freshly saved clip into the library and print its new path
  rename <id> --name=<name>
  set-game --game=<game> <id>...
  favorite <0|1> <id>...
  delete [--local-only] <id>...       Move clips to the trash (and delete them from R2 on the next sync, unless --local-only)
  trim <id> <start> <end> [--precise] [--replace]
                                      Keep [start, end] seconds, as a new clip or in place of the old one

Clips are named by id so they can share display names. Any other video in the folder (including the old
<Game>/<name>.mp4 layout) is adopted on the next index: renamed to <id>.<ext>, keeping its name as the
display name and taking its game from the folder it was in.
"""
import argparse
import hashlib
import json
import os
import re
import sqlite3
import subprocess
import sys
import time
import uuid
from concurrent.futures import ThreadPoolExecutor

VIDEO_EXTENSIONS = {".mp4", ".mkv", ".mov", ".webm", ".flv", ".avi"}
STEAM_ROOT = os.path.expanduser("~/.local/share/Steam")
UNSORTED = "Unsorted"
DEFAULT_NAME = "Untitled"
DB_NAME = ".clips.db"
INCOMING = ".incoming"  # Files on their way into the library; hidden so indexing leaves them alone
UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
RAW_NAME_RE = re.compile(r"^Replay_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}$")  # gpu-screen-recorder's own names
SETTLE_SECONDS = 5  # Don't adopt files modified more recently than this, they may still be written
STAMP_PATH = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "qs-clips-library.stamp")

SCHEMA_VERSION = 3
SCHEMA = """
CREATE TABLE IF NOT EXISTS clips (
    id TEXT PRIMARY KEY,                    -- uuid, also the file name: <library>/<id><ext>
    ext TEXT NOT NULL DEFAULT '.mp4',
    name TEXT NOT NULL DEFAULT 'Untitled',
    game TEXT NOT NULL DEFAULT '',          -- '' is shown as Unsorted
    created REAL NOT NULL,                  -- When it was recorded (unix seconds)
    modified REAL NOT NULL,                 -- Last metadata edit; the newer side wins when syncing
    favorite INTEGER NOT NULL DEFAULT 0,
    source TEXT,                            -- Clip this one was cut from
    imported_from TEXT,                     -- Original path of an adopted file
    size INTEGER NOT NULL DEFAULT 0,
    mtime INTEGER NOT NULL DEFAULT 0,       -- File mtime the probed values belong to; 0 = not probed
    sha1 TEXT,                              -- Of the local file, worked out when syncing needs it
    duration REAL NOT NULL DEFAULT 0,
    width INTEGER NOT NULL DEFAULT 0,
    height INTEGER NOT NULL DEFAULT 0,
    fps INTEGER NOT NULL DEFAULT 0,
    has_audio INTEGER NOT NULL DEFAULT 0,
    remote_etag TEXT,                       -- ETag of the video in R2 as of the last sync; set once uploaded
    remote_sha1 TEXT,                       -- That video's SHA-1, to tell which side changed it
    meta_etag TEXT,                         -- ETag of its metadata file in R2 as of the last sync
    pushed REAL NOT NULL DEFAULT 0,         -- `modified` as of the last metadata sync
    meta_base TEXT,                         -- Metadata both sides agreed on at the last sync (JSON), for merging edits
    deleted INTEGER NOT NULL DEFAULT 0      -- Deleted here; the next sync removes it from R2, then the row
);
CREATE TABLE IF NOT EXISTS games (
    name TEXT PRIMARY KEY,
    appid TEXT NOT NULL DEFAULT '',
    class TEXT NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS meta (
    key TEXT PRIMARY KEY,
    value TEXT
);
"""


# ---- Database ----

def connect(library, create=True):
    if create:
        os.makedirs(library, exist_ok=True)
    db = sqlite3.connect(os.path.join(library, DB_NAME), timeout=30)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA journal_mode=WAL")
    db.executescript(SCHEMA)
    migrate(db)
    return db


def migrate(db):
    """Upgrades databases made by older versions of this script, keyed on PRAGMA user_version. New ones start
    out current."""
    if db.execute("PRAGMA user_version").fetchone()[0] < SCHEMA_VERSION:
        db.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")
        db.commit()


def get_meta(db, key, default=None):
    row = db.execute("SELECT value FROM meta WHERE key = ?", (key,)).fetchone()
    return row["value"] if row else default


def set_meta(db, key, value):
    if value is None:
        db.execute("DELETE FROM meta WHERE key = ?", (key,))
    else:
        db.execute("INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                   (key, value))


def get_clips(db, ids):
    marks = ",".join("?" * len(ids))
    return db.execute(f"SELECT * FROM clips WHERE id IN ({marks})", ids).fetchall() if ids else []


def upsert_game(db, name, appid="", wm_class=""):
    if not name:
        return
    db.execute("""
        INSERT INTO games (name, appid, class) VALUES (?, ?, ?)
        ON CONFLICT(name) DO UPDATE SET
            appid = CASE WHEN excluded.appid != '' THEN excluded.appid ELSE games.appid END,
            class = CASE WHEN excluded.class != '' THEN excluded.class ELSE games.class END
    """, (name, appid or "", wm_class or ""))


def clip_path(library, row):
    return os.path.join(library, row["id"] + row["ext"])


def stamp():
    """Tell open viewers the library changed (they watch this file)."""
    try:
        with open(STAMP_PATH, "w", encoding="utf-8") as f:
            f.write(f"{time.time()}\n")
    except OSError:
        pass


def trash(path):
    return subprocess.run(["gio", "trash", "--", path], capture_output=True).returncode == 0


def sanitize(name):
    # Keep in sync with sanitize() in clip.sh
    name = re.sub(r"[™®©]", "", name)
    name = re.sub(r'[/\\:*?"<>|]', "_", name)
    name = re.sub(r"\s+", " ", name)
    return name.strip(" .")[:64]


def game_value(name):
    name = sanitize(name)
    return "" if name == UNSORTED else name


# ---- Video files ----

def probe(path):
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries",
             "stream=codec_type,width,height,avg_frame_rate:format=duration",
             "-of", "json", path],
            capture_output=True, text=True, timeout=20,
        ).stdout
        data = json.loads(out or "{}")
    except (subprocess.SubprocessError, json.JSONDecodeError):
        return {}
    streams = data.get("streams", [])
    video = next((s for s in streams if s.get("codec_type") == "video"), {})
    fps = 0
    try:
        num, den = video.get("avg_frame_rate", "0/1").split("/")
        fps = round(float(num) / float(den)) if float(den) else 0
    except ValueError:
        pass
    return {
        "duration": float(data.get("format", {}).get("duration", 0) or 0),
        "width": video.get("width", 0),
        "height": video.get("height", 0),
        "fps": fps,
        "has_audio": int(any(s.get("codec_type") == "audio" for s in streams)),
    }


def store_probe(db, clip_id, path, meta=None):
    """Record a file's size and video details. Unreadable files stay unprobed so they're tried again."""
    st = os.stat(path)
    meta = meta if meta is not None else probe(path)
    db.execute("""
        UPDATE clips SET size = ?, mtime = ?, sha1 = NULL, duration = ?, width = ?, height = ?, fps = ?, has_audio = ?
        WHERE id = ?
    """, (st.st_size, int(st.st_mtime) if meta.get("duration") else 0, meta.get("duration", 0),
          meta.get("width", 0), meta.get("height", 0), meta.get("fps", 0), meta.get("has_audio", 0), clip_id))


def file_sha1(path):
    digest = hashlib.sha1()
    with open(path, "rb") as f:
        while chunk := f.read(4 * 1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def thumb_path(cache, row, cloud=False):
    name = f"{row['id']}-cloud.jpg" if cloud else f"{row['id']}-{row['mtime']}.jpg"
    return os.path.join(cache, "thumbs", name)


def make_thumbnail(path, out, duration):
    seek = min(1.0, duration / 3) if duration else 0
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-ss", f"{seek:.2f}", "-i", path,
         "-frames:v", "1", "-vf", "scale=640:-2", "-q:v", "4", out],
        capture_output=True, timeout=30,
    )


# ---- Steam art ----

def steam_libraries():
    libraries = [STEAM_ROOT]
    try:
        with open(os.path.join(STEAM_ROOT, "steamapps/libraryfolders.vdf"), encoding="utf-8") as f:
            libraries += re.findall(r'"path"\s+"([^"]+)"', f.read())
    except OSError:
        pass
    return list(dict.fromkeys(libraries))


def steam_appids_by_name():
    appids = {}
    for library in steam_libraries():
        steamapps = os.path.join(library, "steamapps")
        try:
            manifests = [e for e in os.scandir(steamapps) if e.name.startswith("appmanifest_")]
        except OSError:
            continue
        for manifest in manifests:
            try:
                with open(manifest.path, encoding="utf-8", errors="replace") as f:
                    text = f.read(4096)
            except OSError:
                continue
            appid = re.search(r'"appid"\s+"(\d+)"', text)
            name = re.search(r'"name"\s+"([^"]+)"', text)
            if appid and name:
                appids[sanitize(name.group(1)).lower()] = appid.group(1)
    return appids


def steam_art(appid):
    art = {}
    if not appid:
        return art
    wanted = {
        "cover": ("library_600x900.jpg", "library_capsule.jpg"),
        "header": ("header.jpg", "library_header.jpg"),
        "hero": ("library_hero.jpg",),
        "logo": ("logo.png",),
    }
    found = {}
    for root, _, files in os.walk(os.path.join(STEAM_ROOT, "appcache/librarycache", appid)):
        for file in files:
            found.setdefault(file, os.path.join(root, file))
    for kind, names in wanted.items():
        for name in names:
            if name in found:
                art[kind] = found[name]
                break
    return art


# ---- Indexing ----

def read_game_json(folder):
    try:
        with open(os.path.join(folder, ".game.json"), encoding="utf-8") as f:
            saved = json.load(f)
        return saved.get("appid", "") or "", saved.get("class", "") or ""
    except (OSError, json.JSONDecodeError, AttributeError):
        return "", ""


def adopt_files(db, library):
    """Give every video in the folder that isn't a known clip an id and a row."""
    known = {r["id"] for r in db.execute("SELECT id FROM clips")}
    now = time.time()
    for root, dirs, files in os.walk(library):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        rel = os.path.relpath(root, library)
        game = "" if rel == "." else rel.split(os.sep)[0]
        if game and rel == game:
            upsert_game(db, game, *read_game_json(root))
            db.commit()
        for file in files:
            stem, ext = os.path.splitext(file)
            ext = ext.lower()
            if file.startswith(".") or ext not in VIDEO_EXTENSIONS:
                continue
            is_id = bool(UUID_RE.match(stem))
            if not game and is_id and stem in known:
                continue
            path = os.path.join(root, file)
            try:
                st = os.stat(path)
            except OSError:
                continue
            if st.st_size == 0 or now - st.st_mtime < SETTLE_SECONDS:
                continue
            clip_id = stem if is_id and stem not in known else str(uuid.uuid4())
            dest = os.path.join(library, clip_id + ext)
            if dest != path and os.path.exists(dest):
                clip_id = str(uuid.uuid4())
                dest = os.path.join(library, clip_id + ext)
            name = DEFAULT_NAME if is_id or RAW_NAME_RE.match(stem) else stem
            cur = db.execute("""
                INSERT OR IGNORE INTO clips (id, ext, name, game, created, modified, imported_from)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (clip_id, ext, name, game, st.st_mtime, now, None if dest == path else path))
            if cur.rowcount == 0:  # Added by someone else meanwhile
                continue
            if dest != path:
                try:
                    os.rename(path, dest)
                except OSError as e:
                    db.rollback()
                    print(f"Couldn't adopt {path}: {e}", file=sys.stderr)
                    continue
            db.commit()
            known.add(clip_id)
    db.commit()
    remove_empty_game_folders(library)


def remove_empty_game_folders(library):
    """Game folders from the old layout are left with just .game.json once their clips move out."""
    for entry in os.scandir(library):
        if not entry.is_dir(follow_symlinks=False) or entry.name.startswith("."):
            continue
        for root, dirs, files in os.walk(entry.path, topdown=False):
            if [f for f in files if f != ".game.json"] or any(os.path.isdir(os.path.join(root, d)) for d in dirs):
                continue
            try:
                if ".game.json" in files:
                    os.remove(os.path.join(root, ".game.json"))
                os.rmdir(root)
            except OSError:
                pass


def reconcile(db, library):
    """Forget clips whose file is gone (unless R2 still has them) and return the files that need probing."""
    to_probe = []
    for row in db.execute("SELECT id, ext FROM clips WHERE deleted = 1").fetchall():
        if os.path.exists(clip_path(library, row)):  # Restored from the trash
            db.execute("UPDATE clips SET deleted = 0 WHERE id = ?", (row["id"],))
    for row in db.execute("SELECT * FROM clips WHERE deleted = 0").fetchall():
        path = clip_path(library, row)
        try:
            st = os.stat(path)
        except FileNotFoundError:
            if not row["remote_etag"]:
                db.execute("DELETE FROM clips WHERE id = ?", (row["id"],))
            elif row["mtime"]:
                db.execute("UPDATE clips SET mtime = 0, sha1 = NULL WHERE id = ?", (row["id"],))
            continue
        if st.st_size != row["size"] or int(st.st_mtime) != row["mtime"]:
            to_probe.append((row["id"], path))
    db.commit()
    return to_probe


def clip_json(library, cache, row):
    path = clip_path(library, row)
    local = os.path.exists(path)
    thumb = thumb_path(cache, row, cloud=not local)
    return {
        "id": row["id"],
        "path": path if local else "",
        "file": row["id"] + row["ext"],
        "name": row["name"],
        "game": row["game"] or UNSORTED,
        "created": row["created"],
        "modified": row["modified"],
        "favorite": bool(row["favorite"]),
        "size": row["size"],
        "duration": row["duration"],
        "width": row["width"],
        "height": row["height"],
        "fps": row["fps"],
        "hasAudio": bool(row["has_audio"]),
        "thumb": thumb if os.path.exists(thumb) else "",
        "local": local,
        "cloud": bool(row["remote_etag"]),
        "synced": bool(local and row["remote_etag"] and row["sha1"] and row["sha1"] == row["remote_sha1"]),
        "source": row["source"] or "",
    }


def cmd_index(args):
    library, cache = args.library, args.cache
    empty = {"clips": [], "games": [], "totalSize": 0}
    if not os.path.isdir(library):  # Not created yet, or on a drive that isn't mounted
        json.dump(empty, sys.stdout)
        return
    thumbs_dir = os.path.join(cache, "thumbs")
    os.makedirs(thumbs_dir, exist_ok=True)

    db = connect(library)
    adopt_files(db, library)
    to_probe = reconcile(db, library)
    with ThreadPoolExecutor(max_workers=4) as pool:
        probed = list(pool.map(lambda item: (item, probe(item[1])), to_probe))
    for (clip_id, path), meta in probed:
        try:
            store_probe(db, clip_id, path, meta)
        except OSError:
            pass
    db.commit()

    rows = db.execute("SELECT * FROM clips WHERE deleted = 0").fetchall()
    missing_thumbs = [r for r in rows if os.path.exists(clip_path(library, r)) and not os.path.exists(thumb_path(cache, r))]
    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(lambda r: make_thumbnail(clip_path(library, r), thumb_path(cache, r), r["duration"]), missing_thumbs))
    clean_thumbnails(thumbs_dir, rows, cache)

    clips = sorted((clip_json(library, cache, r) for r in rows), key=lambda c: c["created"], reverse=True)
    games_info = {r["name"]: dict(r) for r in db.execute("SELECT * FROM games")}
    appids = None
    games = {}
    for clip in clips:
        game = games.get(clip["game"])
        if game is None:
            info = games_info.get(clip["game"], {})
            game = games[clip["game"]] = {"name": clip["game"], "appid": info.get("appid", ""), "class": info.get("class", ""),
                                          "count": 0, "size": 0, "latest": 0}
            if not game["appid"] and clip["game"] != UNSORTED:
                if appids is None:
                    appids = steam_appids_by_name()
                game["appid"] = appids.get(clip["game"].lower(), "")
            game.update(steam_art(game["appid"]))
        game["count"] += 1
        game["size"] += clip["size"] if clip["local"] else 0
        game["latest"] = max(game["latest"], clip["created"])

    json.dump({
        "clips": clips,
        "games": sorted(games.values(), key=lambda g: g["latest"], reverse=True),
        "totalSize": sum(c["size"] for c in clips if c["local"]),
    }, sys.stdout)


def clean_thumbnails(thumbs_dir, rows, cache):
    keep = {os.path.basename(thumb_path(cache, r)) for r in rows}
    keep |= {os.path.basename(thumb_path(cache, r, cloud=True)) for r in rows if r["remote_etag"]}
    cutoff = time.time() - 600  # Leave anything a running sync may have just fetched
    for entry in os.scandir(thumbs_dir):
        try:
            if entry.name not in keep and entry.stat().st_mtime < cutoff:
                os.remove(entry.path)
        except OSError:
            pass


# ---- Edits ----

def cmd_add(args):
    library = args.library
    db = connect(library)
    ext = os.path.splitext(args.file)[1].lower() or ".mp4"
    clip_id = str(uuid.uuid4())
    dest = os.path.join(library, clip_id + ext)
    now = time.time()
    game = game_value(args.game or "")
    upsert_game(db, game, args.appid, args.wm_class)
    db.execute("INSERT INTO clips (id, ext, name, game, created, modified) VALUES (?, ?, ?, ?, ?, ?)",
               (clip_id, ext, (args.name or "").strip() or DEFAULT_NAME, game, now, now))
    os.rename(args.file, dest)  # Inside the transaction, so an index running now can't half-see it
    db.commit()
    stamp()
    print(dest)


def touch_clips(db, ids, sql, params):
    cur = db.execute(f"UPDATE clips SET {sql}, modified = ? WHERE id IN ({','.join('?' * len(ids))})",
                     (*params, time.time(), *ids))
    db.commit()
    stamp()
    return cur.rowcount


def cmd_rename(args):
    name = " ".join(args.name.split())[:200]
    if not name:
        sys.exit("Name can't be empty")
    touch_clips(connect(args.library), [args.id], "name = ?", (name,))


def cmd_set_game(args):
    db = connect(args.library)
    game = game_value(args.game)
    upsert_game(db, game)
    touch_clips(db, args.ids, "game = ?", (game,))


def cmd_favorite(args):
    touch_clips(connect(args.library), args.ids, "favorite = ?", (1 if args.value == "1" else 0,))


def cmd_delete(args):
    db = connect(args.library)
    failed = 0
    for row in get_clips(db, args.ids):
        if args.local_only and not (row["remote_etag"] and row["sha1"] and row["sha1"] == row["remote_sha1"]):
            continue  # R2 doesn't have this exact file, so this copy can't go
        path = clip_path(args.library, row)
        if os.path.exists(path) and not trash(path):
            failed += 1
            continue
        if args.local_only:
            db.execute("UPDATE clips SET mtime = 0, sha1 = NULL WHERE id = ?", (row["id"],))
        elif row["remote_etag"]:
            db.execute("UPDATE clips SET deleted = 1 WHERE id = ?", (row["id"],))
        else:
            db.execute("DELETE FROM clips WHERE id = ?", (row["id"],))
    db.commit()
    stamp()
    if failed:
        sys.exit(f"Couldn't move {failed} clip(s) to the trash")


def cmd_trim(args):
    library = args.library
    db = connect(library)
    rows = get_clips(db, [args.id])
    if not rows or not os.path.exists(clip_path(library, rows[0])):
        sys.exit("Clip not found")
    row = rows[0]
    src = clip_path(library, row)
    os.makedirs(os.path.join(library, INCOMING), exist_ok=True)
    new_id = row["id"] if args.replace else str(uuid.uuid4())
    tmp = os.path.join(library, INCOMING, f"{new_id}.trim{row['ext']}")

    codec = (["-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-c:a", "aac", "-b:a", "192k"] if args.precise
             else ["-c", "copy", "-avoid_negative_ts", "make_zero"])
    result = subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{args.start:.3f}", "-to", f"{args.end:.3f}",
                             "-i", src, *codec, "-movflags", "+faststart", tmp], capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(tmp):
        if os.path.exists(tmp):
            os.remove(tmp)
        sys.exit(result.stderr.strip() or "ffmpeg failed")
    meta = probe(tmp)
    now = time.time()

    if args.replace:
        if not trash(src):  # The original goes to the trash rather than being overwritten for good
            os.remove(tmp)
            sys.exit("Couldn't move the original to the trash")
        os.rename(tmp, src)
        store_probe(db, row["id"], src, meta)
        db.execute("UPDATE clips SET modified = ? WHERE id = ?", (now, row["id"]))
        dest = src
    else:
        dest = os.path.join(library, new_id + row["ext"])
        db.execute("""
            INSERT INTO clips (id, ext, name, game, created, modified, source) VALUES (?, ?, ?, ?, ?, ?, ?)
        """, (new_id, row["ext"], row["name"], row["game"], now, now, row["id"]))
        os.rename(tmp, dest)
        store_probe(db, new_id, dest, meta)
    db.commit()
    stamp()
    print(json.dumps({"id": new_id, "path": dest}))


def main():
    parser = argparse.ArgumentParser(description="Clip library")
    parser.add_argument("--library", required=True)
    parser.add_argument("--cache", default=os.path.expanduser("~/.cache/quickshell/clips"))
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("index").set_defaults(func=cmd_index)

    p = sub.add_parser("add")
    p.add_argument("file")
    p.add_argument("--name", default="")
    p.add_argument("--game", default="")
    p.add_argument("--appid", default="")
    p.add_argument("--class", dest="wm_class", default="")
    p.set_defaults(func=cmd_add)

    # Free text goes in --opt=value form so a leading "-" can't pass for an option
    p = sub.add_parser("rename")
    p.add_argument("id")
    p.add_argument("--name", required=True)
    p.set_defaults(func=cmd_rename)

    p = sub.add_parser("set-game")
    p.add_argument("--game", required=True)
    p.add_argument("ids", nargs="+")
    p.set_defaults(func=cmd_set_game)

    p = sub.add_parser("favorite")
    p.add_argument("value", choices=["0", "1"])
    p.add_argument("ids", nargs="+")
    p.set_defaults(func=cmd_favorite)

    p = sub.add_parser("delete")
    p.add_argument("--local-only", action="store_true", help="Keep the copy in R2")
    p.add_argument("ids", nargs="+")
    p.set_defaults(func=cmd_delete)

    p = sub.add_parser("trim")
    p.add_argument("id")
    p.add_argument("start", type=float)
    p.add_argument("end", type=float)
    p.add_argument("--precise", action="store_true", help="Re-encode for frame-accurate cuts")
    p.add_argument("--replace", action="store_true", help="Replace the clip instead of saving a new one")
    p.set_defaults(func=cmd_trim)

    args = parser.parse_args()
    args.library = os.path.expanduser(args.library)
    args.cache = os.path.expanduser(args.cache)
    args.func(args)


if __name__ == "__main__":
    main()
