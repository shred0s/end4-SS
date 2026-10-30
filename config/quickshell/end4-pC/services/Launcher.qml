pragma Singleton

import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * What Super and the dock's launcher button open: the overview (search and
 * workspaces) or the start menu. Also keeps what the start menu shows: its
 * pinned apps, recently opened files and an icon file for every app.
 */
Singleton {
    id: root

    readonly property bool startMenu: Config.options.launcher.style === "startMenu"
    readonly property bool isOpen: root.startMenu ? GlobalStates.startMenuOpen : GlobalStates.overviewOpen
    // Clicking the dock button while the launcher is open ends its focus grab
    // first, which closes it; that click mustn't open it again.
    property real closedAt: 0

    Connections {
        target: GlobalStates
        function onStartMenuOpenChanged() {
            if (GlobalStates.startMenuOpen) root.refreshRecent();
            else root.closedAt = Date.now();
        }
        function onOverviewOpenChanged() {
            if (!GlobalStates.overviewOpen) root.closedAt = Date.now();
        }
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) GlobalStates.startMenuOpen = false;
        }
    }

    // So the first open already lists recent files
    Component.onCompleted: root.refreshRecent()

    // screenName: where the start menu opens; empty for the focused monitor
    function open(screenName) {
        if (!root.startMenu) {
            GlobalStates.overviewOpen = true;
            return;
        }
        GlobalStates.overviewOpen = false;
        GlobalStates.startMenuScreen = screenName || (WM.focusedMonitor?.name ?? "");
        GlobalStates.startMenuOpen = true;
    }

    function close() {
        GlobalStates.startMenuOpen = false;
        GlobalStates.overviewOpen = false;
    }

    function toggle(screenName) {
        if (root.isOpen) root.close();
        else root.open(screenName);
    }

    function toggleFromClick(screenName) {
        if (!root.isOpen && Date.now() - root.closedAt < 300) return;
        root.toggle(screenName);
    }

    // Pinned to Start, as desktop entries. Until something is pinned, the
    // dock's pinned apps stand in.
    readonly property list<string> pinnedIds: Config.options.startMenu.pinnedApps.length > 0
        ? Config.options.startMenu.pinnedApps
        : Config.options.dock.pinnedApps
    readonly property var pinnedEntries: {
        void DesktopEntries.applications.values;
        const seen = new Set();
        return root.pinnedIds.map(id => DesktopEntries.heuristicLookup(id)).filter(entry => {
            if (!entry || entry.noDisplay || seen.has(entry.id)) return false;
            seen.add(entry.id);
            return true;
        });
    }

    function isPinned(entry) {
        return root.pinnedEntries.some(pinned => pinned.id === entry?.id);
    }

    function togglePin(entry) {
        const ids = root.pinnedEntries.map(pinned => pinned.id);
        Config.options.startMenu.pinnedApps = root.isPinned(entry)
            ? ids.filter(id => id !== entry.id)
            : ids.concat([entry.id]);
    }

    function moveToFront(entry) {
        const ids = root.pinnedEntries.map(pinned => pinned.id).filter(id => id !== entry.id);
        Config.options.startMenu.pinnedApps = [entry.id].concat(ids);
    }

    // Recently opened files, newest first: {path, name, mime, time}
    property list<var> recentFiles: []
    readonly property string recentScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/startmenu/recent_files.py`)

    function refreshRecent() {
        if (!Config.options.startMenu.showRecent || recentProc.running) return;
        recentProc.running = true;
    }

    Process {
        id: recentProc
        command: ["python3", root.recentScriptPath, "6"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.recentFiles = JSON.parse(text);
                } catch (e) {
                    console.warn("[Launcher] Could not list recent files:", e);
                }
            }
        }
    }

    // Icon files by icon name. Theme icons only load on the UI thread (KDE's
    // icon loader isn't thread-safe), and a long app list loading them stalls
    // the shell, so app icons load as plain files in the background instead.
    property var iconFiles: ({})
    readonly property string iconTheme: SystemAppearance.iconTheme
    readonly property var appIconNames: [...new Set(AppSearch.list.map(app => app.icon).filter(name => name && !name.startsWith("/")))]
    onIconThemeChanged: resolveTimer.restart()
    onAppIconNamesChanged: resolveTimer.restart()
    onStartMenuChanged: resolveTimer.restart()

    function iconFor(entry) {
        const name = entry?.icon ?? "";
        if (name.startsWith("/")) return "file://" + name;
        const file = root.iconFiles[name];
        if (file) return "file://" + file;
        return SystemAppearance.iconPath(name, "application-x-executable");
    }

    Timer {
        id: resolveTimer
        // Desktop entries arrive one by one while they're scanned; let them settle
        interval: 2000
        onTriggered: {
            if (!root.startMenu || root.iconTheme === "") return;
            if (iconResolver.running) {
                resolveTimer.restart();
                return;
            }
            iconResolver.command = ["python3", SystemAppearance.iconResolverPath, root.iconTheme].concat(root.appIconNames);
            iconResolver.running = true;
        }
    }

    Process {
        id: iconResolver
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.iconFiles = JSON.parse(text);
                } catch (e) {
                    console.warn("[Launcher] Could not resolve icons:", e);
                }
            }
        }
    }
}
