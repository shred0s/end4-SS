pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/*
 * The clip library as the Clips app (clips.qml) sees it: clips and their metadata from the library
 * database (clips_db.py), edits, and Cloudflare R2 sync (clips_r2.py). The replay buffer belongs to
 * the shell's Clips service, so buffer buttons here reach it over IPC.
 */
Singleton {
    id: root

    readonly property string dbScriptPath: `${Directories.scriptPath}/videos/clips_db.py`
    readonly property string syncScriptPath: `${Directories.scriptPath}/videos/clips_r2.py`
    readonly property string clipScriptPath: `${Directories.scriptPath}/videos/clip.sh`
    readonly property string keybindsScriptPath: `${Directories.scriptPath}/videos/clip_keybinds.sh`
    readonly property string shellPath: Quickshell.shellPath("shell.qml")
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string socketPath: `${runtimeDir}/qs-clips.sock`
    readonly property string stampPath: `${runtimeDir}/qs-clips-library.stamp` // Touched by every library change
    readonly property string syncStatusPath: `${runtimeDir}/qs-clips-sync.json`
    readonly property string cacheDir: FileUtils.trimFileProtocol(`${Directories.cache}/clips`)
    readonly property string savePath: (Config.options.clips.savePath || "").replace(/^~/, FileUtils.trimFileProtocol(Directories.home))

    // Library
    property list<var> clips: []
    property list<var> games: []
    property real totalSize: 0
    property bool loading: false
    property bool loaded: false
    property string requestedClipId: "" // The viewer opens this clip once it's indexed
    property bool refreshQueued: false
    property string lastIndexText: ""
    property bool started: false

    // Replay buffer, as reported by gpu-screen-recorder
    property bool running: false
    property bool bufferBusy: false // A start/stop/save request is on its way to the shell

    // Cloudflare R2
    property bool cloudConnected: false
    property bool cloudConnecting: false
    property string cloudEndpoint: ""
    property string cloudBucket: ""
    property string cloudMessage: "" // Why connecting didn't work
    property var syncStatus: ({})
    property list<string> downloadRequests: []
    property real now: Date.now() / 1000
    // A sync that hasn't written progress in two minutes died without saying so
    readonly property bool syncing: (root.syncStatus.running ?? false) && root.now - (root.syncStatus.updated ?? 0) < 120

    function start() {
        if (root.started) return;
        root.started = true;
        // File watching needs the files to exist
        root.exec(["bash", "-c", 'touch -- "$1" "$2"', "_", root.stampPath, root.syncStatusPath], () => {
            stampFile.reload();
            syncStatusFile.reload();
        });
        root.refresh();
        root.checkCloud();
    }

    // ---- Library ----
    function refresh() {
        if (!Config.ready || !root.savePath) return;
        if (indexProc.running) {
            root.refreshQueued = true;
            return;
        }
        root.loading = true;
        indexProc.running = true;
    }
    function find(id) {
        return root.clips.find(c => c.id === id) ?? null;
    }
    function openClip(id) {
        root.requestedClipId = id;
        root.refresh();
    }

    function db(args, callback) {
        root.exec(["python3", "-I", root.dbScriptPath, "--library", root.savePath, "--cache", root.cacheDir, ...args], callback);
    }
    // Show an edit right away; the index catches up once the database has it
    function patchClips(ids, changes) {
        root.clips = root.clips.map(c => ids.includes(c.id) ? Object.assign({}, c, changes) : c);
    }
    function afterEdit(code, errorMessage) {
        if (code !== 0 && errorMessage) root.notifyError(errorMessage);
        root.refresh();
        root.scheduleSync();
    }

    function setFavorite(ids, favorite) {
        if (ids.length === 0) return;
        root.patchClips(ids, { favorite: favorite });
        root.db(["favorite", favorite ? "1" : "0", ...ids], code => root.afterEdit(code, Translation.tr("Couldn't update favorites")));
    }
    function toggleFavorite(id) {
        const clip = root.find(id);
        if (clip) root.setFavorite([id], !clip.favorite);
    }
    function rename(id, newName) {
        const name = newName.trim();
        if (name.length === 0) return;
        root.patchClips([id], { name: name });
        root.db(["rename", id, `--name=${name}`], code => root.afterEdit(code, Translation.tr("Couldn't rename clip")));
    }
    function moveToGame(ids, game) {
        const name = game.trim();
        if (name.length === 0 || ids.length === 0) return;
        root.patchClips(ids, { game: name });
        root.db(["set-game", `--game=${name}`, ...ids], code => root.afterEdit(code, Translation.tr("Couldn't change the game")));
    }
    // localOnly keeps the copy in R2, so the clip stays in the library as cloud-only
    function trash(ids, localOnly) {
        if (ids.length === 0) return;
        if (localOnly) root.patchClips(ids, { local: false, path: "" });
        else root.clips = root.clips.filter(c => !ids.includes(c.id));
        root.db(["delete", ...(localOnly ? ["--local-only"] : []), ...ids],
            code => root.afterEdit(code, Translation.tr("Couldn't move clips to trash")));
    }
    // Keeps [start, end] seconds as a new clip, or in place of this one (the original goes to the trash)
    function trim(id, start, end, precise, replace, callback) {
        root.db(["trim", id, start.toFixed(3), end.toFixed(3), ...(precise ? ["--precise"] : []), ...(replace ? ["--replace"] : [])], code => {
            root.afterEdit(code, replace ? Translation.tr("Couldn't save the edit") : Translation.tr("Couldn't trim clip"));
            callback?.(code === 0);
        });
    }

    function copyFile(path) {
        Quickshell.execDetached(["bash", "-c", 'printf "file://%s\\n" "$1" | wl-copy -t text/uri-list', "_", path]);
    }
    function copyPath(path) {
        Quickshell.clipboardText = path;
    }
    function showInFolder(path) {
        Quickshell.execDetached(["bash", "-c",
            'if command -v dolphin >/dev/null; then dolphin --select "$1"; else xdg-open "$(dirname "$1")"; fi',
            "_", path]);
    }
    function openFolder() {
        Qt.openUrlExternally(`file://${root.savePath}`);
    }
    function openExternally(path) {
        Qt.openUrlExternally(`file://${path}`);
    }

    // ---- Replay buffer (owned by the shell) ----
    // Falls back to running clip.sh directly when the shell isn't there to ask
    function bufferCommand(ipcFunction, fallbackArgs) {
        root.bufferBusy = true;
        root.exec(["bash", "-c", 'qs ipc -p "$1" call clips "$2" >/dev/null 2>&1 || "${@:3}"', "_",
            root.shellPath, ipcFunction, root.clipScriptPath, ...fallbackArgs], () => bufferBusyTimer.restart());
    }
    function toggleBuffer() {
        root.bufferCommand("toggle", ["toggle"]);
    }
    function saveClip() {
        root.bufferCommand("save", ["save", `${Config.options.clips.clipSeconds}`]);
    }
    function saveBuffer() {
        root.bufferCommand("saveBuffer", ["save", "0"]);
    }

    // ---- Hotkeys and sound ----
    // Writes the shortcuts into Hyprland's config and reloads it
    function applyShortcuts() {
        const shortcuts = Config.options.clips.shortcuts;
        root.exec([root.keybindsScriptPath, shortcuts.save, shortcuts.saveBuffer, shortcuts.toggle, shortcuts.openApp], code => {
            if (code !== 0) root.notifyError(Translation.tr("Couldn't update the Hyprland shortcuts"));
        });
    }
    function playSound(path) {
        const file = (path || "").trim().replace(/^~/, FileUtils.trimFileProtocol(Directories.home));
        if (file) Quickshell.execDetached(["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", file]);
    }

    // ---- Cloudflare R2 ----
    function syncCommand() {
        return ["python3", "-I", root.syncScriptPath, "--library", root.savePath, "--cache", root.cacheDir];
    }
    function checkCloud() {
        if (!cloudStatusProc.running) cloudStatusProc.running = true;
    }
    // Checked before it's saved. Passed through the environment so the secret stays off the command line.
    function connectCloud(endpoint, bucket, accessKeyId, secretAccessKey) {
        if (connectProc.running) return;
        root.cloudMessage = "";
        connectProc.environment = {
            R2_ENDPOINT: endpoint.trim(),
            R2_BUCKET: bucket.trim(),
            R2_ACCESS_KEY_ID: accessKeyId.trim(),
            R2_SECRET_ACCESS_KEY: secretAccessKey.trim()
        };
        connectProc.running = true;
    }
    // Forgets the keys and what was uploaded; the bucket itself is left alone
    function disconnectCloud() {
        root.exec([...root.syncCommand(), "disconnect"], () => {
            root.checkCloud();
            root.refresh();
        });
    }
    // Uploads only what's asked for, and keeps already uploaded clips in step both ways. Detached so
    // transfers carry on after the app closes; progress comes back through the status file.
    function sync(extraArgs) {
        if (!root.cloudConnected) return;
        Quickshell.execDetached([...root.syncCommand(), "sync", ...(extraArgs ?? [])]);
    }
    function scheduleSync() {
        if (root.cloudConnected) syncDebounce.restart();
    }
    function download(ids) {
        const wanted = ids.filter(id => !root.downloadRequests.includes(id));
        if (wanted.length === 0) return;
        root.downloadRequests = [...root.downloadRequests, ...wanted];
        root.sync(["--download", ...wanted]);
    }
    function upload(ids) {
        if (ids.length > 0) root.sync(["--upload", ...ids]);
    }
    function removeFromCloud(ids) {
        if (ids.length > 0) root.sync(["--unlink", ...ids]);
    }
    // The running transfer for a clip, if any
    function transferFor(id) {
        return root.syncing && root.syncStatus.id === id ? root.syncStatus : null;
    }
    function applySyncStatus(text) {
        let status;
        try {
            status = JSON.parse(text);
        } catch (e) {
            return; // Caught mid-write; the next change has all of it
        }
        const wasRunning = root.syncStatus.running ?? false;
        root.syncStatus = status;
        root.now = Date.now() / 1000;
        if (status.running) return;
        const finished = status.downloads ?? [];
        if (finished.length > 0) root.downloadRequests = root.downloadRequests.filter(id => !finished.includes(id));
        if (status.signedOut) root.checkCloud();
        if (wasRunning) root.refresh();
    }

    // ---- Helpers for display ----
    function formatSize(bytes) {
        if (bytes >= 1024 ** 3) return `${(bytes / 1024 ** 3).toFixed(1)} GB`;
        if (bytes >= 1024 ** 2) return `${Math.round(bytes / 1024 ** 2)} MB`;
        return `${Math.max(1, Math.round(bytes / 1024))} KB`;
    }
    function formatDuration(seconds) {
        const s = Math.max(0, Math.floor(seconds));
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        const sec = `${s % 60}`.padStart(2, "0");
        return h > 0 ? `${h}:${`${m}`.padStart(2, "0")}:${sec}` : `${m}:${sec}`;
    }
    function formatRelative(unixSeconds) {
        const diff = Date.now() / 1000 - unixSeconds;
        if (diff < 60) return Translation.tr("Just now");
        if (diff < 3600) return Translation.tr("%1 min ago").arg(Math.floor(diff / 60));
        if (diff < 86400) return Translation.tr("%1 h ago").arg(Math.floor(diff / 3600));
        if (diff < 86400 * 7) return Translation.tr("%1 d ago").arg(Math.floor(diff / 86400));
        return Qt.formatDate(new Date(unixSeconds * 1000), "d MMM yyyy");
    }

    function notifyError(message) {
        Quickshell.execDetached(["notify-send", message, "-a", "Clips", "-u", "critical"]);
    }

    // ---- Plumbing ----
    function exec(command, callback) {
        const proc = commandComponent.createObject(root, { command: command, callback: callback ?? null });
        proc.running = true;
    }

    Component {
        id: commandComponent
        Process {
            property var callback
            onExited: (exitCode, exitStatus) => {
                callback?.(exitCode);
                destroy();
            }
        }
    }

    Process {
        id: indexProc
        command: ["python3", "-I", root.dbScriptPath, "--library", root.savePath, "--cache", root.cacheDir, "index"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text === root.lastIndexText) return;
                root.lastIndexText = text;
                try {
                    const data = JSON.parse(text);
                    root.clips = data.clips;
                    root.games = data.games;
                    root.totalSize = data.totalSize;
                    root.loaded = true;
                } catch (e) {
                    console.warn("[ClipLibrary] Failed to parse index:", e);
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.loading = false;
            if (root.refreshQueued) {
                root.refreshQueued = false;
                root.refresh();
            }
        }
    }

    FileView {
        id: stampFile
        path: root.stampPath
        watchChanges: true
        onFileChanged: stampDebounce.restart()
    }
    Timer {
        id: stampDebounce
        interval: 300
        onTriggered: root.refresh()
    }
    Timer { // Pick up files dropped into the folder by hand
        interval: 60000
        repeat: true
        running: root.started
        onTriggered: root.refresh()
    }

    Process {
        id: statusProc
        command: ["gsr-cli", "-ipc", root.socketPath, "status"]
        onExited: (exitCode, exitStatus) => root.running = (exitCode === 0)
    }
    Timer {
        interval: 2000
        repeat: true
        running: root.started
        triggeredOnStart: true
        onTriggered: if (!statusProc.running) statusProc.running = true
    }
    Timer {
        id: bufferBusyTimer
        interval: 1500 // Long enough for the shell to have started saving or toggling
        onTriggered: {
            root.bufferBusy = false;
            if (!statusProc.running) statusProc.running = true;
        }
    }

    Process {
        id: cloudStatusProc
        command: [...root.syncCommand(), "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const status = JSON.parse(text);
                    const wasConnected = root.cloudConnected;
                    root.cloudConnected = status.connected;
                    root.cloudEndpoint = status.endpoint ?? "";
                    root.cloudBucket = status.bucket ?? "";
                    if (status.connected) root.cloudMessage = "";
                    else if (status.error) root.cloudMessage = status.error; // Saved keys that R2 now refuses
                    if (root.cloudConnected && !wasConnected) root.sync(); // Catch up with other devices
                } catch (e) {
                    console.warn("[ClipLibrary] Failed to read R2 status:", e);
                }
            }
        }
    }
    Process {
        id: connectProc
        command: [...root.syncCommand(), "connect"]
        onRunningChanged: root.cloudConnecting = running
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    if (!result.ok) root.cloudMessage = result.error;
                } catch (e) {
                    root.cloudMessage = Translation.tr("Couldn't check the R2 details");
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            connectProc.environment = {};
            root.checkCloud();
        }
    }
    FileView {
        id: syncStatusFile
        path: root.syncStatusPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.applySyncStatus(text())
    }
    Timer {
        id: syncDebounce
        interval: 2000
        onTriggered: root.sync()
    }
    Timer { // Pull in what other devices did while the app stays open
        interval: 5 * 60 * 1000
        repeat: true
        running: root.cloudConnected
        onTriggered: if (!root.syncing) root.sync()
    }
    Timer {
        interval: 30000
        repeat: true
        running: root.syncing
        onTriggered: root.now = Date.now() / 1000
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) root.start();
        }
    }
    Connections {
        target: Config.options.clips
        function onSavePathChanged() {
            root.lastIndexText = "";
            root.refresh();
        }
    }
    Component.onCompleted: {
        if (Config.ready) root.start();
    }
}
