# Clips on Proton Drive: handoff

This folder belongs to **Clips**, a game-clip app on a Linux desktop (Quickshell on Hyprland, recording
with gpu-screen-recorder). The user picks clips in that app and uploads them here with the `proton-drive`
CLI. This file explains the layout so another app can show them, starting with a **small read-only SwiftUI
viewer for iPhone and Mac**.

The desktop re-uploads this file whenever its own copy changes, so edits made here get overwritten. The
source is `~/.config/quickshell/end4-pC/scripts/videos/clips_proton_handoff.md` on the desktop.

## What the viewer should do

- List the clips newest first as thumbnails with name, game, length and date. Filter by game and
  favorites, and search by name.
- Play a clip, with previous/next.
- Read-only to start with. If it ever writes, follow the rules at the end.
- Run on iPhone and on the user's Mac: one SwiftUI codebase (iOS 17+ / macOS 14+), as a multiplatform
  target.

## Layout

```
/my-files/Quickshell Clips/        the app's own folder; nothing else in the Drive is touched
├── HANDOFF.md                     this file
├── Videos/                        clip files and nothing else
│   └── <clipId>.mp4
└── Metadata/                      one JSON per clip, same id
    └── <clipId>.json
```

- `clipId` is a lowercase UUID.
- A clip counts as available once **both** of its files exist. The desktop uploads the video first and
  the JSON after it.
- Proton Drive files can't carry custom properties, which is why the metadata is a separate file.

## Getting at the files: use Proton's own apps, not an API

Proton Drive is end-to-end encrypted, and there's no simple REST API with OAuth for third-party apps. Don't
reimplement Proton's auth and crypto. Read the folder through the Proton Drive apps, which decrypt locally
and expose the files to other apps:

- **Mac:** the Proton Drive app shows up in Finder through Apple's File Provider, under
  `~/Library/CloudStorage/` (a `ProtonDrive-…` folder). Files there download on demand when opened.
- **iPhone/iPad:** the Proton Drive app adds a location to the Files app, also through File Provider.
- **In the viewer:**
  - Let the user pick the `Quickshell Clips` folder once with `.fileImporter(allowedContentTypes: [.folder])`.
  - Keep a **security-scoped bookmark** to it (`url.bookmarkData(options: .withSecurityScope)` on macOS,
    `.minimalBookmark` on iOS).
  - Call `startAccessingSecurityScopedResource()` while reading.
- **Reading:** read files through `NSFileCoordinator` (`coordinate(readingItemAt:)`). That makes the File
  Provider download a file before it's read. Videos are 50–150 MB, so show progress or a spinner while a
  clip downloads, then hand the local URL to `AVPlayer`.
- **Verify early:** check that the Proton Drive app on the device can see the folder. If its File Provider
  integration is off or missing on a platform, that's the thing to fix first.

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
| `id` | Same as the file names. The clip's identity on every device. |
| `name` | Display name. **Not unique**: many clips are just "Untitled". |
| `game` | Game name. Empty means "Unsorted". |
| `steamAppId` | Steam app id, when known. For art, use `https://cdn.cloudflare.steamstatic.com/steam/apps/<id>/header.jpg` (also `library_hero.jpg`, `library_600x900.jpg`, `logo.png`). |
| `windowClass` | Window class of the game at recording time. |
| `created` | When it was recorded, in unix seconds. Sort by this. |
| `modified` | Last metadata edit, in unix seconds. |
| `favorite` | Bool. |
| `source` | `id` of the clip this one was trimmed from, or empty. |
| `ext`, `size`, `sha1` | The video file's extension, byte size and SHA-1 (as uploaded). |
| `duration`, `width`, `height`, `fps`, `hasAudio` | Video details. |
| `thumbnail` | A small JPEG (320 px wide) as a data URI, for the grid without touching the video. |

- Ignore unknown fields, and skip files that fail to parse.

## Video format

- MP4 with H.264 (High profile) video, mostly 1080p at 60–120 fps.
- Audio is AAC on everything recorded since late October 2026. At least one older clip has **Opus** audio
  in MP4. AVPlayer may play that clip without sound or refuse it. Handle the failure gracefully: show an
  error, or offer to play without sound.

## If the viewer ever writes

The desktop syncs both ways:

- **Deleting:** removing a clip's two files (to Proton's trash) makes the desktop trash its local copy on
  the next sync. Only do it when the user explicitly deletes a clip.
- **Editing:** to change `name`, `game`, `favorite`, `created` or `source`, rewrite the JSON with the new
  value **and** set `modified` to the current unix time.
  - The desktop merges field by field: a field changed on only one side keeps that change, and a field
    changed on both sides goes to the newer `modified`.
  - Always write the whole object back, keeping fields you don't use.
- **Never:**
  - rename files or change a video's content;
  - put other files in `Videos/` or `Metadata/`;
  - create one of the two files without the other.

## Suggested shape

- `ClipFolder`: owns the bookmark. It reads `Metadata/*.json` into `[Clip]` (cheap, thanks to the embedded
  thumbnails), and resolves `Videos/<id><ext>` to a downloaded local URL on demand.
- `ClipStore` (`@Observable`): clips sorted by `created`, the game list, favorite and game filters, search.
- Views:
  - first-run "Choose your Quickshell Clips folder";
  - a `NavigationSplitView` with games in the sidebar and a `LazyVGrid` of clip cards (thumbnail,
    duration badge, name, game · relative date);
  - a player using `VideoPlayer`, with previous/next and a download spinner;
  - refresh on appear and on pull.

## Desktop side, for reference

- Sync: `~/.config/quickshell/end4-pC/scripts/videos/clips_proton.py`, which runs the `proton-drive` CLI.
- Local library: `clips_db.py`. SQLite at `~/Videos/clips/.clips.db`, with files named `<clipId><ext>`.
