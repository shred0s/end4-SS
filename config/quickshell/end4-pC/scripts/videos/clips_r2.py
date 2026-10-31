#!/usr/bin/env python3
"""Cloudflare R2 sync for the clip library.

Usage: clips_r2.py [--library <dir> --cache <dir>] <command>

  status                          Whether R2 is set up and reachable, as JSON
  connect                         Check and save the R2 details given in the environment as R2_ENDPOINT (account ID or
                                  S3 address), R2_BUCKET, R2_ACCESS_KEY_ID and R2_SECRET_ACCESS_KEY, which keeps the
                                  secret off the command line. Prints {"ok": true} or {"ok": false, "error": ...}
  disconnect                      Forget the R2 details and what was uploaded; the bucket is left as it is
  sync [--upload ID...] [--download ID...] [--unlink ID...]

Only clips picked with --upload go to R2. From then on syncing keeps them in step both ways (names, games,
favorites, edits and deletions) and brings in clips uploaded from other devices, as cloud-only until downloaded.

The bucket should be the app's own, with an API token that can't reach anything else. Its layout:
    HANDOFF.md              how this works, for building other viewers
    library.json            marks the bucket as this library's; a new one (bucket emptied or swapped) starts afresh
    Videos/<id>.mp4         clip files, each with its SHA-1 in x-amz-meta-sha1
    Metadata/<id>.json      each clip's name, game, dates, favorite, video details and a small thumbnail
R2 keeps no trash or old versions, so deleting or replacing something there is final.

The R2 details live in ~/.config/qs-clips/r2.json, readable only by you. Sync progress is written to
$XDG_RUNTIME_DIR/qs-clips-sync.json so the viewer can show syncs that another process started.
Exit codes: 0 ok, 1 error, 3 not set up, or R2 refused the keys.
"""
import argparse
import base64
import contextlib
import fcntl
import hashlib
import json
import mimetypes
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.parse
import uuid

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import clips_db  # noqa: E402
import clips_s3  # noqa: E402

CONFIG_PATH = os.environ.get("QS_CLIPS_R2_CONFIG") or os.path.join(
    os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "qs-clips", "r2.json")
_prefix = (os.environ.get("QS_CLIPS_R2_PREFIX") or "").strip("/")  # Lets tests use a corner of the bucket
PREFIX = f"{_prefix}/" if _prefix else ""
VIDEOS = f"{PREFIX}Videos/"
METADATA = f"{PREFIX}Metadata/"
HANDOFF_KEY = f"{PREFIX}HANDOFF.md"
MARKER_KEY = f"{PREFIX}library.json"
HANDOFF_PATH = os.path.join(os.path.dirname(os.path.realpath(__file__)), "clips_r2_handoff.md")
METADATA_VERSION = 1
MERGED_FIELDS = ("name", "game", "favorite", "created", "source")  # Metadata edits merge field by field
UNLINKED = {"remote_etag": None, "remote_sha1": None, "meta_etag": None, "pushed": 0, "meta_base": None}
STATUS_PATH = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "qs-clips-sync.json")
MAX_UPLOAD = 5 * 1000 ** 3  # R2 takes up to about 5 GB in one go
ACCOUNT_RE = re.compile(r"^[0-9a-f]{32}$")
EXIT_ERROR, EXIT_SIGNED_OUT = 1, 3


class SyncError(Exception):
    pass


# ---- R2 ----

def load_config():
    try:
        with open(CONFIG_PATH, encoding="utf-8") as f:
            config = json.load(f)
    except (OSError, ValueError):
        return None
    keys = ("endpoint", "bucket", "accessKeyId", "secretAccessKey")
    return config if isinstance(config, dict) and all(config.get(k) for k in keys) else None


def save_config(config):
    os.makedirs(os.path.dirname(CONFIG_PATH), mode=0o700, exist_ok=True)
    tmp = CONFIG_PATH + ".tmp"
    with contextlib.suppress(FileNotFoundError):
        os.remove(tmp)
    with os.fdopen(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w", encoding="utf-8") as f:
        json.dump(config, f, indent=1)
    os.replace(tmp, CONFIG_PATH)


def client(config):
    return clips_s3.Client(config["endpoint"], config["bucket"], config["accessKeyId"], config["secretAccessKey"],
                           config.get("region") or "auto")


def parse_endpoint(text):
    """An account ID, or the S3 address R2 shows (perhaps with the bucket on the end): (endpoint, bucket or "")."""
    text = text.strip()
    if ACCOUNT_RE.match(text.lower()):
        return f"https://{text.lower()}.r2.cloudflarestorage.com", ""
    url = urllib.parse.urlsplit(text if "://" in text else f"https://{text}")
    if url.scheme not in ("http", "https") or not url.netloc:
        raise ValueError(text)
    return f"{url.scheme}://{url.netloc}", url.path.strip("/").split("/")[0]


def refused(error):
    """R2 turned the keys or the bucket down, as opposed to the network or R2 having a bad moment."""
    return error.status in (401, 403) or error.code == "NoSuchBucket"


def describe(error, bucket=""):
    if error.status == 401 or error.code in ("InvalidAccessKeyId", "SignatureDoesNotMatch", "Unauthorized"):
        return "R2 didn't accept the access keys"
    if error.code == "NoSuchBucket":
        return f"There's no bucket called “{bucket}”" if bucket else "That bucket doesn't exist"
    if error.status == 403:
        return "The access keys aren't allowed to do that. They need Object Read & Write on the bucket"
    return str(error)


def files_by_id(objects, folder, ext=None):
    """Objects named <folder><clip id><ext>, by clip id."""
    files = {}
    for obj in objects:
        name = obj["key"][len(folder):]
        stem, suffix = os.path.splitext(name)
        if "/" not in name and clips_db.UUID_RE.match(stem) and (ext is None or suffix.lower() == ext):
            files.setdefault(stem, obj)
    return files


def md5_and_sha1(path):
    md5, sha1 = hashlib.md5(), hashlib.sha1()
    with open(path, "rb") as f:
        while chunk := f.read(1 << 20):
            md5.update(chunk)
            sha1.update(chunk)
    return md5.hexdigest(), sha1.hexdigest()


def number(value, cast=float):
    try:
        return cast(value)
    except (TypeError, ValueError):
        return 0


def forget_remote(db):
    db.execute(f"UPDATE clips SET {', '.join(f'{k} = ?' for k in UNLINKED)}", tuple(UNLINKED.values()))


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
    def __init__(self, db, s3, args, status):
        self.db = db
        self.s3 = s3
        self.args = args
        self.status = status
        self.library = args.library
        self.cache = args.cache
        incoming = os.path.join(self.library, clips_db.INCOMING)
        os.makedirs(incoming, exist_ok=True)
        # Scratch space inside the library, so a finished download is just a rename away
        self.work = tempfile.mkdtemp(prefix="sync-", dir=incoming)
        self.games = {}
        self.pulls = {}  # Clip id -> metadata object to fetch
        self.pushes = set()  # Clip ids whose metadata needs uploading
        self.new_clips = {}  # Clip id -> (video object, its SHA-1), for clips only R2 has
        self.uploaded = set()  # Their metadata goes up with them
        self.orphans = []  # Metadata keys whose video is gone

    def run(self):
        db = self.db
        target = self.ensure_layout()
        if target != clips_db.get_meta(db, "sync_target"):
            # First sync, another bucket, or the bucket was emptied: nothing here is up there yet, and clips
            # missing from it don't mean they were deleted
            forget_remote(db)
            clips_db.set_meta(db, "sync_target", target)
            db.commit()
        videos = files_by_id(self.s3.list(VIDEOS), VIDEOS)
        metadata = files_by_id(self.s3.list(METADATA), METADATA, ".json")
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
                    self.push_metadata([clip_id])  # Right away, so other devices see it before the rest are up
                else:
                    self.download(row)
            except clips_s3.S3Error as e:
                if refused(e):
                    raise
                errors.append(f"{row['name']}: {describe(e)}")
            except (SyncError, OSError) as e:
                errors.append(f"{row['name']}: {e}")
            db.commit()
            clips_db.stamp()

        self.status.update(phase="listing", id="", name="", progress=0)
        self.games = self.load_games()
        self.push_metadata(self.pushes - self.uploaded)
        for key in self.orphans:
            try:
                self.s3.delete(key)
            except clips_s3.S3Error:
                pass  # Just tidying up; the next sync tries again
        db.commit()
        clips_db.stamp()
        if errors:
            more = f" (and {len(errors) - 1} more)" if len(errors) > 1 else ""
            raise SyncError(errors[0] + more)

    def row(self, clip_id):
        return self.db.execute("SELECT * FROM clips WHERE id = ?", (clip_id,)).fetchone()

    def update(self, clip_id, changes):
        if changes:
            self.db.execute(f"UPDATE clips SET {', '.join(f'{k} = ?' for k in changes)} WHERE id = ?",
                            (*changes.values(), clip_id))

    def load_games(self):
        return {r["name"]: dict(r) for r in self.db.execute("SELECT * FROM games")}

    def ensure_layout(self):
        """Marks the bucket as this library's if it isn't yet and refreshes HANDOFF.md. Returns where the library
        lives: the bucket plus the marker's id, which only changes if the bucket is emptied or swapped."""
        library_id = ""
        if found := self.s3.get_bytes(MARKER_KEY):
            with contextlib.suppress(ValueError, AttributeError):
                library_id = str(json.loads(found[0]).get("id") or "")
        if not library_id:
            library_id = str(uuid.uuid4())
            marker = {"app": "Quickshell Clips", "id": library_id, "created": time.time(), "layout": 1}
            self.s3.put(MARKER_KEY, json.dumps(marker, indent=1).encode(), "application/json")
        self.ensure_handoff()
        return f"{self.s3.host}/{self.s3.bucket}/{PREFIX}#{library_id}"

    def ensure_handoff(self):
        try:
            with open(HANDOFF_PATH, "rb") as f:
                content = f.read()
        except OSError:
            return
        current = self.s3.head(HANDOFF_KEY)
        if current is None or current["etag"] != hashlib.md5(content).hexdigest():
            self.s3.put(HANDOFF_KEY, content, "text/markdown; charset=utf-8")

    def remote_keys(self, clip_id, videos, metadata):
        """Pops a clip's objects out of the listings and returns their keys, video first."""
        keys = []
        if (video := videos.pop(clip_id, None)) is not None:
            keys.append(video["key"])
        if (meta := metadata.pop(clip_id, None)) is not None:
            keys.append(meta["key"])
        return keys

    def apply_deletions(self, videos, metadata):
        db = self.db
        keys, deleted, unlinked = [], [], []
        for row in db.execute("SELECT id FROM clips WHERE deleted = 1").fetchall():
            keys += self.remote_keys(row["id"], videos, metadata)
            deleted.append(row["id"])
        for clip_id in self.args.unlink:  # "Remove from the cloud", keeping the file here
            keys += self.remote_keys(clip_id, videos, metadata)
            unlinked.append(clip_id)
        for key in keys:
            self.s3.delete(key)
        for clip_id in deleted:
            db.execute("DELETE FROM clips WHERE id = ?", (clip_id,))
        for clip_id in unlinked:
            row = self.row(clip_id)
            if row is None:
                continue
            if os.path.exists(clips_db.clip_path(self.library, row)):
                self.update(clip_id, UNLINKED)
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
                if meta is not None:
                    self.orphans.append(meta["key"])
                if row["remote_etag"]:
                    self.removed_remotely(row, path, local)
                elif local and clip_id in args.upload:
                    uploads.append(clip_id)
                continue

            if meta is None:
                # Missing metadata comes from whoever has the video, so a device that hasn't seen any yet doesn't
                # overwrite the uploader's with blanks
                if local or row["meta_base"]:
                    self.pushes.add(clip_id)
            elif meta["etag"] != row["meta_etag"]:
                self.pulls[clip_id] = meta  # Changed elsewhere; merged once it's read
            elif row["modified"] > row["pushed"] + 0.001:
                self.pushes.add(clip_id)

            remote_sha1 = self.video_sha1(row, video)
            linked = {"remote_etag": video["etag"], "remote_sha1": remote_sha1}
            if not local:
                self.update(clip_id, {**linked, "size": video["size"]})
                if clip_id in args.download:
                    downloads.append(clip_id)
                continue
            sha1 = row["sha1"] or self.local_sha1(row, path)
            base = row["remote_sha1"]  # What both sides had at the last sync
            if sha1 == remote_sha1:
                self.update(clip_id, linked)
            elif base and remote_sha1 == base:  # Edited here
                uploads.append(clip_id)
            elif base and sha1 == base:  # Edited on another device
                downloads.append(clip_id)
            else:  # Edited on both, or never compared
                self.split_conflict(row, path)
                self.update(clip_id, {**linked, "size": video["size"], "mtime": 0, "sha1": None})
                downloads.append(clip_id)

        # Clips only R2 has, uploaded from another device. Their details come with the metadata.
        for clip_id, video in videos.items():
            self.new_clips[clip_id] = (video, self.video_sha1(None, video))
            if (meta := metadata.pop(clip_id, None)) is not None:
                self.pulls[clip_id] = meta
            if clip_id in args.download:
                downloads.append(clip_id)
        self.orphans += [m["key"] for m in metadata.values()]
        return uploads, downloads

    def video_sha1(self, row, video):
        """SHA-1 of a video in R2: known already if it's the one last synced, otherwise kept with the object."""
        if row is not None and row["remote_etag"] == video["etag"] and row["remote_sha1"]:
            return row["remote_sha1"]
        info = self.s3.head(video["key"]) or {}
        return info.get("metadata", {}).get("sha1") or None

    def split_conflict(self, row, path):
        """The video changed both here and on another device. R2 keeps no old versions, so rather than replace
        either edit, this copy becomes a clip of its own and the original takes the other device's version."""
        fields = {k: row[k] for k in row.keys() if k not in UNLINKED}
        fields.update(id=str(uuid.uuid4()), name=f"{row['name']} (edited here)"[:200], source=row["id"],
                      modified=time.time(), imported_from=None)
        os.rename(path, clips_db.clip_path(self.library, fields))
        self.db.execute(f"INSERT INTO clips ({', '.join(fields)}) VALUES ({', '.join('?' * len(fields))})",
                        tuple(fields.values()))

    def removed_remotely(self, row, path, local):
        """It was in R2 and isn't anymore: deleted on another device, or in the bucket itself."""
        if local and not clips_db.trash(path):
            self.update(row["id"], UNLINKED)
            return
        self.db.execute("DELETE FROM clips WHERE id = ?", (row["id"],))

    def local_sha1(self, row, path):
        sha1 = clips_db.file_sha1(path)
        self.db.execute("UPDATE clips SET sha1 = ? WHERE id = ?", (sha1, row["id"]))
        return sha1

    # ---- Metadata ----

    def pull_metadata(self):
        fetched = {}
        for clip_id, meta in self.pulls.items():
            found = self.s3.get_bytes(meta["key"])
            if found is None:
                continue
            try:
                data = json.loads(found[0])
            except ValueError:
                continue
            if isinstance(data, dict):
                fetched[clip_id] = (data, found[1])
        for clip_id, (video, sha1) in self.new_clips.items():
            data, etag = fetched.get(clip_id, ({}, None))
            self.insert_remote(clip_id, video, sha1, data, etag)
        for clip_id, (data, etag) in fetched.items():
            if clip_id not in self.new_clips:
                self.merge(self.row(clip_id), data, etag)

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

    def merge(self, row, data, meta_etag):
        """Three-way merge against what both sides last agreed on: a field changed on one side only takes that
        change, and only a field changed on both goes to the newer edit."""
        if row is None:
            return
        remote = self.metadata_fields(data)
        local = {k: row[k] for k in MERGED_FIELDS}
        try:
            base = json.loads(row["meta_base"] or "{}")
        except ValueError:
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
        changes = {"meta_etag": meta_etag, "pushed": remote["modified"], "meta_base": json.dumps({k: remote[k] for k in MERGED_FIELDS})}
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

    def insert_remote(self, clip_id, video, sha1, data, meta_etag):
        fields = self.metadata_fields(data) if data else {
            "name": clips_db.DEFAULT_NAME, "game": "", "favorite": 0, "created": video["modified"], "modified": 0, "source": None}
        base = json.dumps({k: fields[k] for k in MERGED_FIELDS}) if data else None
        ext = str(data.get("ext") or os.path.splitext(video["key"])[1] or ".mp4").lower()
        details = self.details(data)
        self.db.execute("""
            INSERT OR IGNORE INTO clips (id, ext, name, game, created, modified, favorite, source, size, duration,
                                         width, height, fps, has_audio, remote_etag, remote_sha1, meta_etag, pushed, meta_base)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (clip_id, ext, fields["name"], fields["game"], fields["created"], fields["modified"], fields["favorite"],
              fields["source"], video["size"], details.get("duration", 0), details.get("width", 0),
              details.get("height", 0), details.get("fps", 0), details.get("has_audio", 0), video["etag"],
              sha1, meta_etag, fields["modified"], base))
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
        for clip_id in ids:
            row = self.row(clip_id)
            if row is None or not row["remote_etag"]:  # Only beside a video that's up there
                continue
            body = json.dumps(self.metadata_for(row), indent=1).encode()
            etag = self.s3.put(f"{METADATA}{clip_id}.json", body, "application/json")
            self.update(clip_id, {"meta_etag": etag, "pushed": row["modified"],
                                  "meta_base": json.dumps({k: row[k] for k in MERGED_FIELDS})})

    # ---- Transfers ----

    def progress(self, value):
        self.status.update(throttle=True, progress=value)

    def upload(self, row):
        path = clips_db.clip_path(self.library, row)
        if os.path.getsize(path) > MAX_UPLOAD:
            raise SyncError("it's too big for R2 to take in one go (5 GB)")
        sha1 = row["sha1"] or self.local_sha1(row, path)
        etag = self.s3.put(f"{VIDEOS}{row['id']}{row['ext']}", path, mimetypes.guess_type(path)[0] or "video/mp4",
                           {"sha1": sha1}, self.progress)
        self.update(row["id"], {"remote_etag": etag, "remote_sha1": sha1})
        self.uploaded.add(row["id"])

    def download(self, row):
        clip_id = row["id"]
        part = os.path.join(self.work, f"{clip_id}{row['ext']}")
        etag = self.s3.get_file(f"{VIDEOS}{clip_id}{row['ext']}", part, self.progress)
        md5, sha1 = md5_and_sha1(part)
        if len(etag) == 32 and md5 != etag:  # A single-part upload's ETag is its MD5
            os.remove(part)
            raise SyncError("the download got corrupted on the way, try again")
        dest = clips_db.clip_path(self.library, row)
        if os.path.exists(dest):  # Edited elsewhere: the old version goes to the trash, as R2 keeps no history
            clips_db.trash(dest)
        os.replace(part, dest)
        clips_db.store_probe(self.db, clip_id, dest)
        self.update(clip_id, {"sha1": sha1, "remote_sha1": sha1, "remote_etag": etag})


# ---- Commands ----

def cmd_status(args):
    config = load_config()
    status = {"connected": False, "endpoint": "", "bucket": "", "error": ""}
    if config:
        status.update(endpoint=config["endpoint"], bucket=config["bucket"])
        try:
            client(config).list(PREFIX, limit=1)
            status["connected"] = True
        except clips_s3.S3Error as e:  # Unless R2 refused, most likely offline; the details are still good
            status.update(connected=not refused(e), error=describe(e, config["bucket"]))
    json.dump(status, sys.stdout)


def cmd_connect(args):
    def fail(message):
        print(json.dumps({"ok": False, "error": message}))
        sys.exit(EXIT_ERROR)

    env = os.environ
    try:
        endpoint, url_bucket = parse_endpoint(env.get("R2_ENDPOINT", ""))
    except ValueError:
        fail("That isn't an account ID or an S3 address")
    config = {"endpoint": endpoint, "bucket": env.get("R2_BUCKET", "").strip() or url_bucket,
              "accessKeyId": env.get("R2_ACCESS_KEY_ID", "").strip(),
              "secretAccessKey": env.get("R2_SECRET_ACCESS_KEY", "").strip()}
    for key, label in (("bucket", "bucket name"), ("accessKeyId", "access key ID"), ("secretAccessKey", "secret access key")):
        if not config[key]:
            fail(f"The {label} is missing")
    s3 = client(config)
    probe = f"{PREFIX}.clips-connect-test"
    try:
        s3.list(PREFIX, limit=1)
        s3.put(probe, b"ok", "text/plain")  # The keys have to be able to write, too
        s3.delete(probe)
    except clips_s3.S3Error as e:
        fail(describe(e, config["bucket"]))
    save_config(config)
    print(json.dumps({"ok": True, "bucket": config["bucket"]}))


def cmd_disconnect(args):
    with contextlib.suppress(FileNotFoundError):
        os.remove(CONFIG_PATH)
    if args.library and os.path.isdir(args.library):
        db = clips_db.connect(args.library)
        db.execute("DELETE FROM clips WHERE deleted = 1")
        forget_remote(db)
        clips_db.set_meta(db, "sync_target", None)
        db.commit()
        clips_db.stamp()


def cmd_sync(args):
    config = load_config()
    if not config:
        sys.exit(EXIT_SIGNED_OUT)
    if not os.path.isdir(args.library):
        sys.exit("The clips folder doesn't exist")
    lock = open(os.path.join(args.library, ".clips-sync.lock"), "w")
    fcntl.flock(lock, fcntl.LOCK_EX)  # One sync at a time; later ones wait their turn

    status = Status(args.download)
    db = clips_db.connect(args.library)
    sync = Sync(db, client(config), args, status)
    try:
        sync.run()
    except clips_s3.S3Error as e:
        db.commit()
        message = describe(e, config["bucket"])
        status.finish(message, signed_out=refused(e))
        sys.exit(EXIT_SIGNED_OUT if refused(e) else f"Sync failed: {message}")
    except (SyncError, OSError, sqlite3.Error, subprocess.TimeoutExpired) as e:
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
    parser = argparse.ArgumentParser(description="Cloudflare R2 sync for clips")
    parser.add_argument("--library", default="")
    parser.add_argument("--cache", default=os.path.expanduser("~/.cache/quickshell/clips"))
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("status").set_defaults(func=cmd_status)
    sub.add_parser("connect").set_defaults(func=cmd_connect)
    sub.add_parser("disconnect").set_defaults(func=cmd_disconnect)

    p = sub.add_parser("sync")
    p.add_argument("--upload", nargs="+", action="extend", default=[], metavar="ID")
    p.add_argument("--download", nargs="+", action="extend", default=[], metavar="ID")
    p.add_argument("--unlink", nargs="+", action="extend", default=[], metavar="ID", help="Remove from R2, keep here")
    p.set_defaults(func=cmd_sync)

    args = parser.parse_args()
    args.library = os.path.expanduser(args.library)
    args.cache = os.path.expanduser(args.cache)
    if args.command == "sync" and not args.library:
        parser.error("sync needs --library")
    args.func(args)


if __name__ == "__main__":
    main()
