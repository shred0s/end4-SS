pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The desktop trash (home trash plus per-drive .Trash-$UID folders), kept in sync
 * by watching the trash folders. Actions go through scripts/trash/trash.py.
 */
Singleton {
    id: root

    readonly property string scriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/trash/trash.py`)

    property list<var> items: []
    readonly property int count: items.length
    readonly property real totalSize: items.reduce((sum, item) => sum + item.size, 0)
    property bool loaded: false
    property bool busy: actionProc.running || root.actionQueue.length > 0
    property string lastError: ""
    property var actionQueue: []

    signal actionFinished(string action, var result)

    function refresh() {
        if (listProc.running) {
            refreshDebounce.restart();
            return;
        }
        listProc.running = true;
    }

    function restore(ids) {
        root.queueAction("restore", ids);
    }

    function remove(ids) {
        root.queueAction("delete", ids);
    }

    function empty() {
        root.queueAction("empty", []);
    }

    function queueAction(action, ids) {
        root.actionQueue = root.actionQueue.concat([{ action: action, ids: ids }]);
        root.runNextAction();
    }

    function runNextAction() {
        if (actionProc.running || root.actionQueue.length === 0) return;
        const next = root.actionQueue[0];
        root.actionQueue = root.actionQueue.slice(1);
        actionProc.action = next.action;
        actionProc.command = ["python3", root.scriptPath, next.action].concat(next.ids);
        actionProc.running = true;
    }

    function formatSize(bytes) {
        const units = ["B", "KB", "MB", "GB", "TB"];
        let value = bytes;
        let unit = 0;
        while (value >= 1000 && unit < units.length - 1) {
            value /= 1000;
            unit++;
        }
        return unit === 0 ? `${value} ${units[0]}` : `${value.toFixed(value < 10 ? 1 : 0)} ${units[unit]}`;
    }

    // DeletionDate is local time without an offset, which Date() parses as local.
    function friendlyDate(isoDate) {
        const date = new Date(isoDate);
        if (isNaN(date.getTime())) return "";
        const minutes = Math.floor((Date.now() - date.getTime()) / 60000);
        if (minutes < 1) return Translation.tr("Just now");
        if (minutes < 60) return Translation.tr("%1 min ago").arg(minutes);
        const hours = Math.floor(minutes / 60);
        if (hours < 24) return Translation.tr("%1 h ago").arg(hours);
        const days = Math.floor(hours / 24);
        if (days === 1) return Translation.tr("Yesterday");
        if (days < 7) return Translation.tr("%1 days ago").arg(days);
        return date.toLocaleDateString(Qt.locale(), Locale.ShortFormat);
    }

    function prettyPath(path) {
        const home = FileUtils.trimFileProtocol(Directories.home);
        return path === home || path.startsWith(home + "/") ? "~" + path.slice(home.length) : path;
    }

    Component.onCompleted: root.refresh()

    Timer {
        id: refreshDebounce
        interval: 250
        onTriggered: root.refresh()
    }

    Process {
        id: listProc
        command: ["python3", root.scriptPath, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.items = JSON.parse(text);
                    root.loaded = true;
                } catch (e) {
                    console.warn("[Trash] Could not parse trash listing:", e);
                }
            }
        }
    }

    // Trashing a file writes its .trashinfo in a few steps, so changes are debounced.
    Process {
        id: watchProc
        running: true
        command: ["python3", root.scriptPath, "watch"]
        stdout: SplitParser {
            onRead: refreshDebounce.restart()
        }
        onExited: watchRestart.start()
    }

    Timer {
        id: watchRestart
        interval: 10000
        onTriggered: watchProc.running = true
    }

    Process {
        id: actionProc
        property string action: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let result = { done: [], errors: [] };
                try {
                    result = JSON.parse(text);
                } catch (e) {
                    result.errors = [{ id: "", message: Translation.tr("The trash helper failed") }];
                }
                root.lastError = result.errors.length > 0
                    ? result.errors.map(error => error.message).filter((m, i, all) => all.indexOf(m) === i).join("\n")
                    : "";
                root.actionFinished(actionProc.action, result);
            }
        }
        onExited: {
            root.refresh();
            root.runNextAction();
        }
    }
}
