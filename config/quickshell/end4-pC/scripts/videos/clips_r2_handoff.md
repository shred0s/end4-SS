# Clips in Cloudflare R2: handoff

This bucket belongs to **Clips**, a game-clip app on a Linux desktop (Quickshell on Hyprland, recording with
gpu-screen-recorder). The user picks clips in that app and uploads them here. This file explains the layout so
another app can show and edit them, starting with a **SwiftUI clip app for iPhone and Mac**.

The desktop re-uploads this file whenever its own copy changes, so edits made here get overwritten. The source
is `~/.config/quickshell/end4-pC/scripts/videos/clips_r2_handoff.md` on the desktop.

## What the app should do

- List the clips newest first as thumbnails with name, game, length and date. Filter by game and favorites,
  and search by name.
- Play a clip, with previous/next. Stream it; don't make the user download 100 MB first.
- Edit them too: rename, change game, favorite, trim (in place or as a new clip) and delete, following
  "Editing from the app" below.
- Run on iPhone and on the user's Mac: one SwiftUI codebase (iOS 17+ / macOS 14+), as a multiplatform target.

## Layout

The bucket is the app's own; nothing else lives in it.

```
<bucket>/
├── HANDOFF.md              this file
├── library.json            {"app": "Quickshell Clips", "id": "<uuid>", "created": …, "layout": 1}
├── Videos/<clipId>.mp4     clip files and nothing else
└── Metadata/<clipId>.json  one JSON per clip, same id
```

- `clipId` is a lowercase UUID.
- A clip counts as available once **both** of its objects exist. The desktop uploads the video first and the
  JSON after it.
- Video objects carry their SHA-1 as custom metadata (`x-amz-meta-sha1`). Each is uploaded in a single PUT, so
  its ETag is the MD5 of the file.
- Never touch `library.json`. The desktop uses its `id` to recognise the bucket; a new id makes it treat the
  bucket as a fresh one.

## Getting at the bucket: R2's S3 API

- **Endpoint:** `https://<accountId>.r2.cloudflarestorage.com` (or `<accountId>.eu.r2…` for an EU bucket),
  path-style (`/<bucket>/<key>`), region `auto`, AWS Signature Version 4.
- **Credentials:** the app gets its own R2 API token, made in the Cloudflare dashboard under R2 → API tokens.
  Give it **Object Read & Write**, limited to this bucket. That's an Access Key ID and Secret Access Key.
  - The user types them (plus the endpoint and bucket name) into the app's settings once.
  - Keep them in the **Keychain**. Never hard-code them or put them in UserDefaults.
- **Signing:** hand-roll SigV4 with CryptoKit (about 100 lines; HMAC-SHA256 chain, canonical request), or use
  Soto's S3 module. A small hand-rolled signer keeps dependencies at zero; test it against the AWS SigV4 test
  suite vectors (`get-vanilla` etc.).
- **Listing:** use `GET /<bucket>?list-type=2&prefix=Metadata/`, then follow `NextContinuationToken` while
  `IsTruncated` is true.
- **Metadata:**
  - Fetch each `Metadata/<id>.json`.
  - Cache them on disk keyed by ETag, so a refresh only fetches what changed. The listing gives you ETags for
    free.
- **Playback:**
  - Build a **presigned GET URL** for `Videos/<id><ext>`: query-string SigV4, `X-Amz-Expires` of an hour or
    so.
  - Give it to `AVPlayer`. AVPlayer streams with Range requests, which R2 supports, so playback starts right
    away and seeking works.
  - Nothing has to be downloaded first.
- **Offline (optional, later):** download to the app's caches directory with `URLSession` download tasks.

## Metadata/<clipId>.json

```json
{
 "version": 1,
 "id": "d5e59706-b587-4c05-8de7-698956ce4d2a",
 "name": "Untitled",
 "game": "Overwatch",
 "steamAppId": "2357570",
 "windowClass": "steam_app_2357570",
 "created": 1792767106.42,
 "modified": 1792768000.1,
 "favorite": false,
 "source": "",
 "ext": ".mp4",
 "size": 66772844,
 "sha1": "2b5138a1bb0aa7d7559f7dc9cf3cd1ff85a03d96",
 "duration": 22.6,
 "width": 1920,
 "height": 1080,
 "fps": 60,
 "hasAudio": true,
 "thumbnail": "data:image/jpeg;base64,/9j/4AAQ…"
}
```

| field | meaning |
|-------|---------|
| `id` | Same as the object names. The clip's identity on every device. |
| `name` | Display name. **Not unique**: many clips are just "Untitled". |
| `game` | Game name. Empty means "Unsorted". |
| `steamAppId` | Steam app id, when known. For art, use `https://cdn.cloudflare.steamstatic.com/steam/apps/<id>/header.jpg` (also `library_hero.jpg`, `library_600x900.jpg`, `logo.png`). |
| `windowClass` | Window class of the game at recording time. |
| `created` | When it was recorded, in unix seconds. Sort by this. |
| `modified` | Last metadata edit, in unix seconds. |
| `favorite` | Bool. |
| `source` | `id` of the clip this one was cut from, or empty. Clips named "… (edited here)" are a device's own edit, kept when two devices changed the same clip at once. |
| `ext`, `size`, `sha1` | The video's extension, byte size and SHA-1. |
| `duration`, `width`, `height`, `fps`, `hasAudio` | Video details. |
| `thumbnail` | A small JPEG (320 px wide) as a data URI, for the grid without touching the video. |

- Ignore unknown fields, and skip files that fail to parse.

## Video format

- MP4 with H.264 (High profile) video, mostly 1080p at 60–120 fps.
- Audio is AAC on everything recorded since late October 2026. At least one older clip has **Opus** audio in
  MP4. AVPlayer may play that clip without sound or refuse it. Handle the failure gracefully: show an error, or
  offer to play without sound.

## Editing from the app

The bucket is the shared database: every device edits the objects directly, and the desktop syncs both ways
with whatever it finds. The app can do everything the desktop can, as long as it follows these rules. Editing
needs a token with **Object Read & Write** on the bucket. **R2 keeps no trash or old versions**, so writes are
final. (The desktop moves its own copy of a replaced or deleted clip to its trash, but don't count on it.)

- **Renaming, changing the game, favoriting** (`name`, `game`, `favorite`, `created`, `source`):
  - PUT the whole JSON back with the new values **and** `modified` set to the current unix time.
  - Keep the fields you don't use.
  - The desktop merges field by field: a field changed on only one side keeps that change, and a field changed
    on both sides goes to the newer `modified`.
- **Trimming in place:**
  - Export the trimmed MP4 (`AVAssetExportSession`, passthrough when possible, H.264 + AAC otherwise).
  - PUT it over `Videos/<id><ext>` in **one PUT** with `x-amz-meta-sha1` set to its SHA-1.
  - Then PUT the JSON with new `size`, `sha1`, `duration` (and `width`/`height`/`fps` if they changed), a new
    `thumbnail` if you can, and a bumped `modified`.
  - The desktop downloads the new version on its next sync.
- **Saving a trim as a new clip:**
  - Make a new lowercase UUID.
  - PUT `Videos/<newId>.mp4` (one PUT, with `x-amz-meta-sha1`), then `Metadata/<newId>.json`: a full object
    with `source` set to the original's id and fresh `created` and `modified`.
- **Deleting:** delete both of a clip's objects, the video first. Only do it when the user explicitly deletes a
  clip, after asking. The desktop moves its local copy to the trash on the next sync.
- **Never:**
  - rename objects;
  - upload videos in multiple parts (ETags must stay MD5s, and R2 takes up to 5 GB in one PUT);
  - upload a video without `x-amz-meta-sha1`;
  - put other objects in `Videos/` or `Metadata/`;
  - leave a clip with only one of its two objects;
  - touch `library.json`.
- **Conflicts:** if the desktop and the app change the same video before syncing, the desktop keeps its version
  as a separate clip named "… (edited here)" and takes the app's version for the original id. Nothing is lost.

## Suggested shape

- `R2Client`: SigV4 signing, `list(prefix:)`, `get(key:)`, `put(key:data|file:metadata:)`, `delete(key:)`,
  `presignedURL(key:expires:)`.
- `ClipStore` (`@Observable`):
  - lists `Metadata/` and fetches changed JSONs (cheap, thanks to the embedded thumbnails);
  - holds the clips sorted by `created`, the game list, favorite and game filters, and search.
- Views:
  - first-run "Connect to R2" (endpoint, bucket, key ID, secret; check with a one-item listing before saving);
  - a `NavigationSplitView` with games in the sidebar and a `LazyVGrid` of clip cards (thumbnail, duration
    badge, name, game · relative date);
  - a player using `VideoPlayer` with a presigned URL, plus previous/next;
  - an editor for name, game and favorite, and a trim view (download the clip first, export with AVFoundation,
    then upload as above);
  - refresh on appear and on pull.

## Desktop side, for reference

- Sync: `~/.config/quickshell/end4-pC/scripts/videos/clips_r2.py`, with `clips_s3.py` as its S3 client.
- Local library: `clips_db.py`. SQLite at `~/Videos/clips/.clips.db`, with files named `<clipId><ext>`.
