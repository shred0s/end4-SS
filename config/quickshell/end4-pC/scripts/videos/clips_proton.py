#!/usr/bin/env python3
"""Proton Drive sync for the clip library, done through the proton-drive CLI.

Usage: clips_proton.py [--library <dir> --cache <dir>] <command>

  status                          Whether the CLI is there and signed in, as JSON
  login                           Sign in through the browser; prints JSON lines {"event": "url" | "connected" | "error", ...}
  logout                          Sign out and forget what was uploaded
  sync [--upload ID...] [--download ID...] [--unlink ID...]

Only clips picked with --upload go to Proton Drive. From then on syncing keeps them in step both ways (names, games,
favorites, edits and deletions) and brings in clips uploaded from other devices, as cloud-only until downloaded.

Everything lives in a folder of its own, and nothing outside it is ever read or changed:
    /my-files/Quickshell Clips/
    ├── HANDOFF.md              how this works, for building other viewers
    ├── Videos/<id>.mp4         clip files and nothing else
    └── Metadata/<id>.json      each clip's name, game, dates, favorite, video details and a small thumbnail
Proton Drive files can't carry custom properties, hence the JSON beside each video.

Sync progress is written to $XDG_RUNTIME_DIR/qs-clips-sync.json so the viewer can show syncs that another process
started. Exit codes: 0 ok, 1 error, 3 not signed in (or the CLI is missing).
"""
import argparse
import base64
import fcntl
import hashlib
import json
import os
import pty
import re
import select
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import clips_db  # noqa: E402

ROOT = os.environ.get("QS_CLIPS_PROTON_ROOT") or "/my-files/Quickshell Clips"  # Overridable for testing
VIDEOS = f"{ROOT}/Videos"
METADATA = f"{ROOT}/Metadata"
HANDOFF_NAME = "HANDOFF.md"
HANDOFF_PATH = os.path.join(os.path.dirname(os.path.realpath(__file__)), "clips_proton_handoff.md")
METADATA_VERSION = 1
MERGED_FIELDS = ("name", "game", "favorite", "created", "source")  # Metadata edits merge field by field
STATUS_PATH = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "qs-clips-sync.json")
ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
PROGRESS_RE = re.compile(r"(\d+(?:\.\d+)?)%")
URL_RE = re.compile(r"https://\S+")
STALL_SECONDS = 600  # A transfer that prints nothing for this long is given up on
EXIT_ERROR, EXIT_SIGNED_OUT = 1, 3


class CliError(Exception):
    pass


class SignedOut(CliError):
    pass


class NotFound(CliError):
    pass


# ---- proton-drive CLI ----

def cli_path():
    found = shutil.which("proton-drive")
    if found:
        return found
    fallback = os.path.expanduser("~/.local/bin/proton-drive")
    return fallback if os.access(fallback, os.X_OK) else None


def cli_error(output):
    lines = [line.strip() for line in ANSI_RE.sub("", output).splitlines() if line.strip()]
    if any("login first" in line for line in lines):
        return SignedOut("Not signed in to Proton Drive")
    if any(line.startswith("Node not found") for line in lines):
        return NotFound(lines[-1])
    return CliError(lines[-1] if lines else "proton-drive failed")


def run(command, *args, timeout=300):
    """Runs a proton-drive command with JSON output and returns it parsed."""
    cli = cli_path()
    if not cli:
        raise SignedOut("The proton-drive CLI isn't installed")
    result = subprocess.run([cli, *command, "-j", *args], capture_output=True, text=True, timeout=timeout,
                            stdin=subprocess.DEVNULL)
    if result.returncode != 0:
        raise cli_error(result.stderr + result.stdout)
    try:
        return json.loads(result.stdout or "null")
    except json.JSONDecodeError:
        raise CliError(f"Unexpected output from proton-drive: {result.stdout[:200]}")


def check_transfer(result):
    if result and result.get("failedItems"):
        raise CliError(f"{result['failedItems']} file(s) failed to transfer: {result.get('failures')}")


def run_transfer(command, args, on_progress):
    """Uploads or downloads in a pseudo-terminal, the only place the CLI reports progress."""
    cli = cli_path()
    if not cli:
        raise SignedOut("The proton-drive CLI isn't installed")
    master, slave = pty.openpty()
    proc = subprocess.Popen([cli, *command, *args], stdin=subprocess.DEVNULL, stdout=slave, stderr=slave, close_fds=True)
    os.close(slave)
    output, pending = [], b""
    try:
        while True:
            if not select.select([master], [], [], STALL_SECONDS)[0]:
                proc.kill()
                raise CliError("the transfer stalled")
            try:
                data = os.read(master, 4096)
            except OSError:  # The CLI exited and closed its end
                break
            if not data:
                break
            output.append(data)
            *lines, pending = re.split(rb"[\r\n]", pending + data)
            for line in lines:
                match = PROGRESS_RE.search(ANSI_RE.sub("", line.decode(errors="replace")))
                if match:
                    on_progress(min(1.0, float(match.group(1)) / 100))
    finally:
        os.close(master)
        proc.wait()
    text = ANSI_RE.sub("", b"".join(output).decode(errors="replace"))
    failed = re.search(r"Failed:\s*(\d+)", text)
    if proc.returncode != 0 or (failed and int(failed.group(1)) > 0):
        raise cli_error(text)


def list_folder(path):
    return run(["fs", "list"], path) or []


def trash(paths):
    failed = [item for item in run(["fs", "trash"], *paths) or [] if not item.get("ok")]
    if failed:
        raise CliError(f"Couldn't move {len(failed)} file(s) to the Proton Drive trash")


def node_name(node):
    return (node.get("name") or {}).get("value") or ""


def node_sha1(node):
    return ((node.get("activeRevision") or {}).get("claimedDigests") or {}).get("sha1")


def node_size(node):
    return (node.get("activeRevision") or {}).get("claimedSize") or 0


def node_time(node):
    try:
        return datetime.fromisoformat(node["creationTime"].replace("Z", "+00:00")).timestamp()
    except (KeyError, ValueError):
        return time.time()


def files_by_id(nodes, ext=None):
    """Files named <clip id><ext>, by clip id."""
    files = {}
    for node in nodes:
        stem, suffix = os.path.splitext(node_name(node))
        if node.get("type") == "file" and clips_db.UUID_RE.match(stem) and (ext is None or suffix.lower() == ext):
            files.setdefault(stem, node)
    return files


def number(value, cast=float):
    try:
        return cast(value)
    except (TypeError, ValueError):
        return 0


# ---- Sync ----

class Status:
    """Sync progress for the viewer. Written in place rather than replaced so file watchers keep working."""

    def __init__(self, downloads):
        self.data = {"running": True, "phase": "listing", "id": "", "name": "", "progress": 0, "done": 0, "total": 0,
                     "downloads": downloads, "error": "", "signedOut": False, "updated": 0, "finished": 0}
        self.written = 0
        self.write()

    def update(self, throttle=False, **changes):
        self.data.update(changes)
        if not throttle or time.time() - self.written > 0.3:
            self.write()

    def write(self):
        self.data["updated"] = self.written = time.time()
        try:
            with open(STATUS_PATH, "w", encoding="utf-8") as f:
                json.dump(self.data, f)
        except OSError:
            pass

    def finish(self, error="", signed_out=False):
        self.update(running=False, phase="", id="", name="", progress=0, error=error, signedOut=signed_out,
                    finished=time.time())


class Sync:
    def __init__(self, db, args, status):
        self.db = db
        self.args = args
        self.status = status
        self.library = args.library
        self.cache = args.cache
        incoming = os.path.join(self.library, clips_db.INCOMING)
        os.makedirs(incoming, exist_ok=True)
        # Scratch space inside the library, so a finished download is just a rename away
        self.work = tempfile.mkdtemp(prefix="sync-", dir=incoming)
        self.games = {}
        self.pulls = {}  # Clip id -> metadata node to download
        self.pushes = set()  # Clip ids whose metadata needs uploading
        self.new_clips = {}  # Clip id -> video node, for clips only Proton Drive has
        self.expected_sha1 = {}  # What a downloaded video should hash to
        self.uploaded = {}  # Clip id -> sha1 of what was sent
        self.orphans = []  # Metadata files whose video is gone

    def run(self):
        db = self.db
        root_uid = self.ensure_layout()
        if root_uid != clips_db.get_meta(db, "proton_root"):
            # First sync, another account, or the folder was deleted: nothing here is up there yet, and clips
            # missing from it don't mean they were deleted
            db.execute("UPDATE clips SET remote_id = NULL, remote_sha1 = NULL, meta_sha1 = NULL, pushed = 0, meta_base = NULL")
            clips_db.set_meta(db, "proton_root", root_uid)
            db.commit()
        videos = files_by_id(list_folder(VIDEOS))
        metadata = files_by_id(list_folder(METADATA), ".json")
        self.games = self.load_games()

        self.apply_deletions(videos, metadata)
        uploads, downloads = self.reconcile(videos, metadata)
        self.pull_metadata()
        db.commit()
        clips_db.stamp()

        errors = []
        transfers = [("download", i) for i in downloads] + [("upload", i) for i in uploads]
        for done, (direction, clip_id) in enumerate(transfers):
            row = self.row(clip_id)
            if row is None:
                continue
            self.status.update(phase=direction, id=clip_id, name=row["name"], progress=0, done=done, total=len(transfers))
            try:
                if direction == "upload":
                    self.upload(row)
                else:
                    self.download(row)
            except SignedOut:
                raise
            except (CliError, OSError, subprocess.TimeoutExpired) as e:
                errors.append(f"{row['name']}: {e}")
            db.commit()
            clips_db.stamp()

        self.status.update(phase="listing", id="", name="", progress=0)
        if self.uploaded:
            errors += self.confirm_uploads()
        self.games = self.load_games()
        self.push_metadata(self.pushes | set(self.uploaded))
        if self.orphans:
            try:
                trash(self.orphans)
            except CliError:
                pass  # Just tidying up; the next sync tries again
        db.commit()
        clips_db.stamp()
        if errors:
            more = f" (and {len(errors) - 1} more)" if len(errors) > 1 else ""
            raise CliError(errors[0] + more)

    def row(self, clip_id):
        return self.db.execute("SELECT * FROM clips WHERE id = ?", (clip_id,)).fetchone()

    def update(self, clip_id, changes):
        if changes:
            self.db.execute(f"UPDATE clips SET {', '.join(f'{k} = ?' for k in changes)} WHERE id = ?",
                            (*changes.values(), clip_id))

    def load_games(self):
        return {r["name"]: dict(r) for r in self.db.execute("SELECT * FROM games")}

    def ensure_layout(self):
        """Makes the app's folder and its subfolders if needed, refreshes HANDOFF.md and returns the folder's uid."""
        root_uid = None
        try:
            children = list_folder(ROOT)
        except NotFound:
            root_uid = run(["fs", "create-folder"], os.path.dirname(ROOT), os.path.basename(ROOT))["uid"]
            children = []
        names = {node_name(n): n for n in children}
        for folder in (VIDEOS, METADATA):
            name = os.path.basename(folder)
            node = names.get(name) or run(["fs", "create-folder"], ROOT, name)
            if node.get("type") != "folder":
                raise CliError(f"“{name}” in {ROOT} isn't a folder")
            root_uid = root_uid or node.get("parentUid")
        self.ensure_handoff(names.get(HANDOFF_NAME))
        return root_uid

    def ensure_handoff(self, node):
        try:
            with open(HANDOFF_PATH, "rb") as f:
                content = f.read()
        except OSError:
            return
        if node and node_sha1(node) == hashlib.sha1(content).hexdigest():
            return
        copy = os.path.join(self.work, HANDOFF_NAME)
        with open(copy, "wb") as f:
            f.write(content)
        check_transfer(run(["fs", "upload"], "-t", "-f", "create-new-revision", copy, ROOT))

    def remote_paths(self, clip_id, videos, metadata):
        """Pops a clip's files out of the listings and returns their paths."""
        paths = []
        if (video := videos.pop(clip_id, None)) is not None:
            paths.append(f"{VIDEOS}/{node_name(video)}")
        if (meta := metadata.pop(clip_id, None)) is not None:
            paths.append(f"{METADATA}/{node_name(meta)}")
        return paths

    def apply_deletions(self, videos, metadata):
        db = self.db
        paths, deleted, unlinked = [], [], []
        for row in db.execute("SELECT id FROM clips WHERE deleted = 1").fetchall():
            paths += self.remote_paths(row["id"], videos, metadata)
            deleted.append(row["id"])
        for clip_id in self.args.unlink:  # "Remove from Proton Drive", keeping the file here
            paths += self.remote_paths(clip_id, videos, metadata)
            unlinked.append(clip_id)
        if paths:
            trash(paths)
        for clip_id in deleted:
            db.execute("DELETE FROM clips WHERE id = ?", (clip_id,))
        for clip_id in unlinked:
            row = self.row(clip_id)
            if row is None:
                continue
            if os.path.exists(clips_db.clip_path(self.library, row)):
                self.update(clip_id, {"remote_id": None, "remote_sha1": None, "meta_sha1": None, "pushed": 0, "meta_base": None})
            else:
                db.execute("DELETE FROM clips WHERE id = ?", (clip_id,))
        db.commit()

    def reconcile(self, videos, metadata):
        """Works out which files and metadata have to move, and which way."""
        db, args = self.db, self.args
        uploads, downloads = [], []
        for row in db.execute("SELECT * FROM clips WHERE deleted = 0").fetchall():
            clip_id = row["id"]
            path = clips_db.clip_path(self.library, row)
            local = os.path.exists(path)
            video = videos.pop(clip_id, None)
            meta = metadata.pop(clip_id, None)

            if video is None:
                if row["remote_id"]:
                    self.removed_remotely(row, path, local)
                    if meta is not None:
                        self.orphans.append(f"{METADATA}/{node_name(meta)}")
                elif local and clip_id in args.upload:
                    uploads.append(clip_id)
                continue

            changes = {"remote_id": video["uid"]}
            if meta is None:
                self.pushes.add(clip_id)
            elif node_sha1(meta) != row["meta_sha1"]:
                self.pulls[clip_id] = meta  # Changed elsewhere; the newer edit wins once it's read
            elif row["modified"] > row["pushed"] + 0.001:
                self.pushes.add(clip_id)

            remote_sha1 = node_sha1(video)
            self.expected_sha1[clip_id] = remote_sha1
            if local:
                sha1 = row["sha1"] or self.local_sha1(row, path)
                base = row["remote_sha1"]
                if sha1 == remote_sha1:
                    changes["remote_sha1"] = sha1
                elif base and remote_sha1 == base:  # Edited here
                    uploads.append(clip_id)
                elif base and sha1 == base:  # Edited on another device
                    downloads.append(clip_id)
                else:  # Edited on both, or never compared: keep this copy (Proton keeps the other as a revision)
                    uploads.append(clip_id)
            else:
                changes.update(remote_sha1=remote_sha1, size=node_size(video))
                if clip_id in args.download:
                    downloads.append(clip_id)
            self.update(clip_id, changes)

        # Clips only Proton Drive has, uploaded from another device. Their details come with the metadata.
        for clip_id, video in videos.items():
            self.new_clips[clip_id] = video
            self.expected_sha1[clip_id] = node_sha1(video)
            if (meta := metadata.pop(clip_id, None)) is not None:
                self.pulls[clip_id] = meta
            if clip_id in args.download:
                downloads.append(clip_id)
        self.orphans += [f"{METADATA}/{node_name(m)}" for m in metadata.values()]
        return uploads, downloads

    def removed_remotely(self, row, path, local):
        """It was on Proton Drive and isn't anymore: deleted on another device, or in Proton Drive itself."""
        if local and not clips_db.trash(path):
            self.update(row["id"], {"remote_id": None, "remote_sha1": None, "meta_sha1": None, "pushed": 0, "meta_base": None})
            return
        self.db.execute("DELETE FROM clips WHERE id = ?", (row["id"],))

    def local_sha1(self, row, path):
        sha1 = clips_db.file_sha1(path)
        self.db.execute("UPDATE clips SET sha1 = ? WHERE id = ?", (sha1, row["id"]))
        return sha1

    # ---- Metadata ----

    def pull_metadata(self):
        fetched = {}
        if self.pulls:
            folder = os.path.join(self.work, "pull")
            os.makedirs(folder)
            check_transfer(run(["fs", "download"], "-f", "remove",
                               *[f"{METADATA}/{node_name(m)}" for m in self.pulls.values()], folder, timeout=600))
            for clip_id in self.pulls:
                try:
                    with open(os.path.join(folder, f"{clip_id}.json"), encoding="utf-8") as f:
                        data = json.load(f)
                    if isinstance(data, dict):
                        fetched[clip_id] = data
                except (OSError, json.JSONDecodeError):
                    pass
        for clip_id, video in self.new_clips.items():
            meta_sha1 = node_sha1(self.pulls[clip_id]) if clip_id in fetched else None
            self.insert_remote(clip_id, video, fetched.get(clip_id, {}), meta_sha1)
        for clip_id, data in fetched.items():
            if clip_id not in self.new_clips:
                self.merge(self.row(clip_id), data, node_sha1(self.pulls[clip_id]))

    def details(self, data):
        """Clip fields from a metadata file, for clips that aren't downloaded here."""
        fields = {
            "duration": number(data.get("duration")),
            "width": number(data.get("width"), int),
            "height": number(data.get("height"), int),
            "fps": number(data.get("fps"), int),
            "has_audio": 1 if data.get("hasAudio") else 0,
        }
        return {k: v for k, v in fields.items() if v}

    def metadata_fields(self, data):
        return {
            "name": str(data.get("name") or clips_db.DEFAULT_NAME)[:200],
            "game": clips_db.game_value(str(data.get("game") or "")),
            "favorite": 1 if data.get("favorite") else 0,
            "created": number(data.get("created")) or time.time(),
            "modified": number(data.get("modified")),
            "source": str(data.get("source") or "") or None,
        }

    def merge(self, row, data, meta_sha1):
        """Three-way merge against what both sides last agreed on: a field changed on one side only takes that
        change, and only a field changed on both goes to the newer edit."""
        if row is None:
            return
        remote = self.metadata_fields(data)
        local = {k: row[k] for k in MERGED_FIELDS}
        try:
            base = json.loads(row["meta_base"] or "{}")
        except json.JSONDecodeError:
            base = {}
        remote_newer = remote["modified"] > row["modified"]
        merged = {}
        for key in MERGED_FIELDS:
            if remote[key] == local[key] or (key in base and remote[key] == base[key]):
                merged[key] = local[key]
            elif key in base and local[key] == base[key]:
                merged[key] = remote[key]
            else:
                merged[key] = remote[key] if remote_newer else local[key]
        modified = max(remote["modified"], row["modified"])
        changes = {"meta_sha1": meta_sha1, "pushed": remote["modified"], "meta_base": json.dumps({k: remote[k] for k in MERGED_FIELDS})}
        if merged != local:
            changes.update(merged, modified=modified)
            clips_db.upsert_game(self.db, merged["game"], str(data.get("steamAppId") or ""), str(data.get("windowClass") or ""))
        if merged != {k: remote[k] for k in MERGED_FIELDS} or modified > remote["modified"] + 0.001:
            changes["modified"] = modified
            self.pushes.add(row["id"])
        if not os.path.exists(clips_db.clip_path(self.library, row)):
            changes.update(self.details(data))
            self.save_thumbnail(row["id"], data.get("thumbnail"))
        self.update(row["id"], changes)

    def insert_remote(self, clip_id, video, data, meta_sha1):
        fields = self.metadata_fields(data) if data else {
            "name": clips_db.DEFAULT_NAME, "game": "", "favorite": 0, "created": node_time(video), "modified": 0, "source": None}
        base = json.dumps({k: fields[k] for k in MERGED_FIELDS}) if data else None
        ext = str(data.get("ext") or os.path.splitext(node_name(video))[1] or ".mp4").lower()
        details = self.details(data)
        self.db.execute("""
            INSERT OR IGNORE INTO clips (id, ext, name, game, created, modified, favorite, source, size, duration,
                                         width, height, fps, has_audio, remote_id, remote_sha1, meta_sha1, pushed, meta_base)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (clip_id, ext, fields["name"], fields["game"], fields["created"], fields["modified"], fields["favorite"],
              fields["source"], node_size(video), details.get("duration", 0), details.get("width", 0),
              details.get("height", 0), details.get("fps", 0), details.get("has_audio", 0), video["uid"],
              node_sha1(video), meta_sha1, fields["modified"], base))
        clips_db.upsert_game(self.db, fields["game"], str(data.get("steamAppId") or ""), str(data.get("windowClass") or ""))
        self.save_thumbnail(clip_id, data.get("thumbnail"))

    def save_thumbnail(self, clip_id, data_uri):
        if not isinstance(data_uri, str) or "base64," not in data_uri:
            return
        try:
            image = base64.b64decode(data_uri.split("base64,", 1)[1])
        except ValueError:
            return
        dest = os.path.join(self.cache, "thumbs", f"{clip_id}-cloud.jpg")
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as f:
            f.write(image)

    def thumbnail(self, row):
        """A small JPEG of the clip as a data URI, so devices without the video can still show it."""
        path = clips_db.clip_path(self.library, row)
        sources = [(clips_db.thumb_path(self.cache, row), []), (clips_db.thumb_path(self.cache, row, cloud=True), []),
                   (path, ["-ss", f"{min(1.0, row['duration'] / 3):.2f}"])]
        for source, seek in sources:
            if not os.path.exists(source):
                continue
            result = subprocess.run(["ffmpeg", "-v", "error", *seek, "-i", source, "-frames:v", "1", "-vf", "scale=320:-2",
                                     "-q:v", "6", "-f", "mjpeg", "pipe:1"], capture_output=True, timeout=30)
            if result.returncode == 0 and result.stdout:
                return "data:image/jpeg;base64," + base64.b64encode(result.stdout).decode()
        return ""

    def metadata_for(self, row):
        game = self.games.get(row["game"], {})
        return {
            "version": METADATA_VERSION,
            "id": row["id"],
            "name": row["name"],
            "game": row["game"],
            "steamAppId": game.get("appid", ""),
            "windowClass": game.get("class", ""),
            "created": row["created"],
            "modified": row["modified"],
            "favorite": bool(row["favorite"]),
            "source": row["source"] or "",
            "ext": row["ext"],
            "size": row["size"],
            "sha1": row["remote_sha1"],
            "duration": row["duration"],
            "width": row["width"],
            "height": row["height"],
            "fps": row["fps"],
            "hasAudio": bool(row["has_audio"]),
            "thumbnail": self.thumbnail(row),
        }

    def push_metadata(self, ids):
        folder = os.path.join(self.work, "push")
        os.makedirs(folder, exist_ok=True)
        written = {}
        for clip_id in ids:
            row = self.row(clip_id)
            if row is None or not row["remote_id"]:  # Only beside a video that's up there
                continue
            body = json.dumps(self.metadata_for(row), indent=1).encode()
            with open(os.path.join(folder, f"{clip_id}.json"), "wb") as f:
                f.write(body)
            written[clip_id] = (hashlib.sha1(body).hexdigest(), row["modified"], json.dumps({k: row[k] for k in MERGED_FIELDS}))
        if not written:
            return
        check_transfer(run(["fs", "upload"], "-t", "-f", "create-new-revision",
                           *[os.path.join(folder, f"{i}.json") for i in written], METADATA, timeout=600))
        for clip_id, (sha1, modified, base) in written.items():
            self.update(clip_id, {"meta_sha1": sha1, "pushed": modified, "meta_base": base})

    # ---- Transfers ----

    def progress(self, value):
        self.status.update(throttle=True, progress=value)

    def upload(self, row):
        path = clips_db.clip_path(self.library, row)
        sha1 = row["sha1"] or self.local_sha1(row, path)
        # A new revision for edited clips, so Proton keeps the previous version around
        run_transfer(["fs", "upload"], ["-t", "-f", "create-new-revision", path, VIDEOS], self.progress)
        self.uploaded[row["id"]] = sha1

    def confirm_uploads(self):
        """Checks that what arrived is what was sent, and links the clips to their files."""
        errors = []
        listed = files_by_id(list_folder(VIDEOS))
        for clip_id, sha1 in self.uploaded.items():
            node = listed.get(clip_id)
            if node is None or node_sha1(node) != sha1:
                errors.append(f"{clip_id}: the upload didn't arrive intact, it'll be redone on the next sync")
                continue
            self.update(clip_id, {"remote_id": node["uid"], "remote_sha1": sha1})
        return errors

    def download(self, row):
        clip_id = row["id"]
        name = f"{clip_id}{row['ext']}"
        folder = os.path.join(self.work, f"download-{clip_id}")
        os.makedirs(folder, exist_ok=True)
        run_transfer(["fs", "download"], ["-f", "remove", f"{VIDEOS}/{name}", folder], self.progress)
        part = os.path.join(folder, name)
        if not os.path.exists(part):
            raise CliError("the download didn't arrive")
        sha1 = clips_db.file_sha1(part)
        if self.expected_sha1.get(clip_id) and sha1 != self.expected_sha1[clip_id]:
            os.remove(part)
            raise CliError("the download got corrupted on the way, try again")
        dest = clips_db.clip_path(self.library, row)
        os.replace(part, dest)
        clips_db.store_probe(self.db, clip_id, dest)
        self.update(clip_id, {"sha1": sha1, "remote_sha1": sha1})


# ---- Commands ----

def emit(event, **fields):
    print(json.dumps({"event": event, **fields}), flush=True)


def account():
    """The signed-in account's email, or raises SignedOut."""
    info = run(["fs", "info"], "/my-files", timeout=60)
    return (info or {}).get("ownedBy", {}).get("email", "")


def cmd_status(args):
    status = {"installed": bool(cli_path()), "connected": False, "email": "", "error": ""}
    if status["installed"]:
        try:
            status.update(connected=True, email=account())
        except SignedOut:
            pass
        except (CliError, subprocess.TimeoutExpired) as e:  # Most likely offline; the session is still there
            status.update(connected=True, error=str(e))
    json.dump(status, sys.stdout)


def cmd_login(args):
    cli = cli_path()
    if not cli:
        emit("error", message="The proton-drive CLI isn't installed")
        sys.exit(EXIT_ERROR)
    # It opens the browser itself, and prints the address in case that doesn't work
    master, slave = pty.openpty()
    proc = subprocess.Popen([cli, "auth", "login"], stdin=slave, stdout=slave, stderr=slave, close_fds=True)
    os.close(slave)
    output, url_sent = b"", False
    deadline = time.time() + 600
    while time.time() < deadline:
        if select.select([master], [], [], 1)[0]:
            try:
                data = os.read(master, 4096)
            except OSError:
                break
            if not data:
                break
            output += data
            match = URL_RE.search(ANSI_RE.sub("", output.decode(errors="replace")))
            if match and not url_sent:
                emit("url", url=match.group(0))
                url_sent = True
        elif proc.poll() is not None:
            break
    else:
        proc.kill()
    proc.wait()
    os.close(master)
    if proc.returncode != 0:
        emit("error", message=str(cli_error(output.decode(errors="replace"))) if output else "Sign-in timed out")
        sys.exit(EXIT_ERROR)
    try:
        emit("connected", email=account())
    except CliError as e:
        emit("error", message=str(e))
        sys.exit(EXIT_ERROR)


def cmd_logout(args):
    cli = cli_path()
    if cli:
        subprocess.run([cli, "auth", "logout"], capture_output=True, timeout=60, stdin=subprocess.DEVNULL)
    if args.library and os.path.isdir(args.library):
        db = clips_db.connect(args.library)
        db.execute("DELETE FROM clips WHERE deleted = 1")
        db.execute("UPDATE clips SET remote_id = NULL, remote_sha1 = NULL, meta_sha1 = NULL, pushed = 0, meta_base = NULL")
        clips_db.set_meta(db, "proton_root", None)
        db.commit()
        clips_db.stamp()


def cmd_sync(args):
    if not cli_path():
        sys.exit(EXIT_SIGNED_OUT)
    if not os.path.isdir(args.library):
        sys.exit("The clips folder doesn't exist")
    lock = open(os.path.join(args.library, ".clips-sync.lock"), "w")
    fcntl.flock(lock, fcntl.LOCK_EX)  # One sync at a time; later ones wait their turn

    status = Status(args.download)
    db = clips_db.connect(args.library)
    sync = Sync(db, args, status)
    try:
        sync.run()
    except SignedOut as e:
        db.commit()
        status.finish(str(e), signed_out=True)
        sys.exit(EXIT_SIGNED_OUT)
    except (CliError, OSError, sqlite3.Error, subprocess.TimeoutExpired) as e:
        db.commit()
        status.finish(str(e))
        sys.exit(f"Sync failed: {e}")
    except BaseException as e:
        status.finish(str(e) or type(e).__name__)
        raise
    finally:
        shutil.rmtree(sync.work, ignore_errors=True)
    status.finish()


def main():
    parser = argparse.ArgumentParser(description="Proton Drive sync for clips")
    parser.add_argument("--library", default="")
    parser.add_argument("--cache", default=os.path.expanduser("~/.cache/quickshell/clips"))
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("status").set_defaults(func=cmd_status)
    sub.add_parser("login").set_defaults(func=cmd_login)
    sub.add_parser("logout").set_defaults(func=cmd_logout)

    p = sub.add_parser("sync")
    p.add_argument("--upload", nargs="+", action="extend", default=[], metavar="ID")
    p.add_argument("--download", nargs="+", action="extend", default=[], metavar="ID")
    p.add_argument("--unlink", nargs="+", action="extend", default=[], metavar="ID", help="Remove from Proton Drive, keep here")
    p.set_defaults(func=cmd_sync)

    args = parser.parse_args()
    args.library = os.path.expanduser(args.library)
    args.cache = os.path.expanduser(args.cache)
    if args.command == "sync" and not args.library:
        parser.error("sync needs --library")
    args.func(args)


if __name__ == "__main__":
    main()
