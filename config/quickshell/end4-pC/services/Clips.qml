pragma Singleton
pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/*
 * Instant-replay clipping (gpu-screen-recorder), run by the shell. The clip library itself is the
 * separate Clips app (clips.qml, see ClipLibrary); this opens it.
 */
Singleton {
    id: root

    readonly property string scriptPath: `${Directories.scriptPath}/videos/clip.sh`
    readonly property string appScriptPath: `${Directories.scriptPath}/videos/clips-app.sh`
    readonly property string socketPath: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/qs-clips.sock`

    // Replay buffer state
    property bool running: false
    property bool starting: false
    property bool saving: false
    property string monitor: "" // Monitor the buffer was started on, kept across restarts

    // Automatic clipping while a game runs
    property string activeGame: ""
    property bool autoStarted: false // Buffer was started for activeGame, so stop it when the game closes
    property bool autoSuppressed: false // User stopped clipping during this game, so don't restart it
    property real noGameSince: 0
    // GameMode follows activeGame too, so detection runs while either one wants it
    readonly property bool detectGames: Config.options.clips.autoStartForGames || Config.options.gameMode.autoForGames

    signal clipSaved()

    function load() {}

    // ---- Clip library app ----
    function openViewer(clipId) {
        Quickshell.execDetached([root.appScriptPath, clipId ?? ""]);
    }
    function toggleViewer() {
        Quickshell.execDetached([root.appScriptPath, "--toggle"]);
    }

    // ---- Replay buffer ----
    // start()/stop() are user actions; game detection uses startBuffer()/stopBuffer() directly
    function start() {
        root.autoStarted = false;
        root.autoSuppressed = false;
        root.startBuffer("");
    }
    function stop() {
        root.autoStarted = false;
        if (root.activeGame) root.autoSuppressed = true;
        root.stopBuffer();
    }
    function toggle() {
        if (root.running) root.stop();
        else root.start();
    }
    function startBuffer(monitor, callback) {
        if (root.running || root.starting) return;
        root.starting = true;
        root.monitor = monitor ?? "";
        root.exec([root.scriptPath, "start", root.monitor], code => {
            root.starting = false;
            root.checkStatus();
            if (code === 0) callback?.();
        });
    }
    function stopBuffer(callback) {
        root.exec([root.scriptPath, "stop"], () => {
            root.checkStatus();
            callback?.();
        });
    }
    function restart() {
        if (!root.running) return;
        root.starting = true;
        root.exec([root.scriptPath, "restart", root.monitor], () => {
            root.starting = false;
            root.checkStatus();
        });
    }

    // ---- Game detection ----
    function checkGame() {
        if (!root.detectGames) return;
        if (!gameProc.running) gameProc.running = true;
    }
    function handleGameCheck(line) {
        if (!root.detectGames) return;
        if (line) {
            const [name, appid, windowClass, monitor] = line.split("|");
            root.noGameSince = 0;
            if (root.activeGame !== name) {
                root.activeGame = name;
                root.autoSuppressed = false;
            }
            if (Config.options.clips.autoStartForGames && !root.running && !root.starting && !root.autoSuppressed) {
                root.autoStarted = true;
                root.startBuffer(monitor, () => root.notify(Translation.tr("Clipping started"),
                    Translation.tr("%1 · Alt+F10 saves the last %2 seconds").arg(name).arg(Config.options.clips.clipSeconds)));
            }
        } else if (root.activeGame) {
            // Launchers often close their window before the game opens one, so wait before giving up
            if (root.noGameSince === 0) {
                root.noGameSince = Date.now();
                gameGraceTimer.restart();
            } else if (Date.now() - root.noGameSince >= gameGraceTimer.interval - 500) {
                root.endGameSession();
            }
        }
    }
    function endGameSession() {
        const game = root.activeGame;
        root.activeGame = "";
        root.noGameSince = 0;
        root.autoSuppressed = false;
        if (root.autoStarted && root.running) {
            root.stopBuffer(() => root.notify(Translation.tr("Clipping stopped"), Translation.tr("%1 closed").arg(game)));
        }
        root.autoStarted = false;
    }
    function save(seconds) {
        if (root.saving) return;
        root.saving = true;
        root.exec([root.scriptPath, "save", `${seconds ?? 0}`], code => {
            root.saving = false;
            if (code === 0) root.clipSaved();
        });
    }
    function saveClip() {
        root.save(Config.options.clips.clipSeconds);
    }
    function saveBuffer() {
        root.save(0);
    }
    function checkStatus() {
        statusProc.running = true;
    }

    function notify(title, body) {
        Quickshell.execDetached(["notify-send", title, body, "-a", "Clips", "-i", "media-record", "-t", "4000"]);
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
        id: statusProc
        command: ["gsr-cli", "-ipc", root.socketPath, "status"]
        onExited: (exitCode, exitStatus) => root.running = (exitCode === 0)
    }

    Timer {
        interval: GlobalStates.overlayOpen ? 2000 : 10000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.checkStatus()
    }

    Process {
        id: gameProc
        command: [root.scriptPath, "active-game"]
        stdout: StdioCollector {
            onStreamFinished: root.handleGameCheck(text.trim())
        }
    }
    Connections {
        target: HyprlandData
        function onWindowListChanged() {
            gameDebounce.restart();
        }
    }
    Timer {
        id: gameDebounce
        interval: 1500
        onTriggered: root.checkGame()
    }
    Timer {
        id: gameGraceTimer
        interval: 8000
        onTriggered: root.checkGame()
    }
    Timer { // Fallback in case a window event is missed
        interval: 30000
        repeat: true
        running: Config.ready && root.detectGames
        triggeredOnStart: true
        onTriggered: root.checkGame()
    }

    // Restart the buffer when capture settings change so they take effect
    Connections {
        target: Config.options.clips
        function onBufferSecondsChanged() { restartDebounce.restart() }
        function onFpsChanged() { restartDebounce.restart() }
        function onQualityChanged() { restartDebounce.restart() }
        function onResolutionChanged() { restartDebounce.restart() }
        function onMonitorChanged() { restartDebounce.restart() }
        function onSystemAudioChanged() { restartDebounce.restart() }
        function onMicrophoneChanged() { restartDebounce.restart() }
        function onSavePathChanged() { restartDebounce.restart() }
    }
    Timer {
        id: restartDebounce
        interval: 800
        onTriggered: root.restart()
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready && Config.options.clips.autoStart) autoStartTimer.start();
        }
    }
    Timer {
        id: autoStartTimer
        interval: 3000
        onTriggered: root.start()
    }
    Component.onCompleted: {
        if (Config.ready && Config.options.clips.autoStart) autoStartTimer.start();
    }
}
