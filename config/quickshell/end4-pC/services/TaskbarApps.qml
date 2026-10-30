pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland

Singleton {
    id: root

    // Window app IDs and desktop entry IDs can differ in case (com.obsproject.Studio
    // vs com.obsproject.studio), so pins are matched case-insensitively.
    function isPinned(appId) {
        const id = appId.toLowerCase();
        return Config.options.dock.pinnedApps.some(pinned => pinned.toLowerCase() === id);
    }

    function togglePin(appId) {
        if (root.isPinned(appId)) {
            const id = appId.toLowerCase();
            Config.options.dock.pinnedApps = Config.options.dock.pinnedApps.filter(pinned => pinned.toLowerCase() !== id)
        } else {
            Config.options.dock.pinnedApps = Config.options.dock.pinnedApps.concat([appId])
        }
    }

    function hasWindows(appId) {
        const id = appId.toLowerCase();
        return ToplevelManager.toplevels.values.some(toplevel => toplevel.appId.toLowerCase() === id);
    }

    // Focuses the next (step > 0) or previous window of a dock entry.
    function cycleWindows(entry, step) {
        const toplevels = entry?.toplevels ?? [];
        if (toplevels.length === 0) return;
        const current = toplevels.findIndex(toplevel => toplevel.activated);
        const next = current === -1
            ? (step > 0 ? 0 : toplevels.length - 1)
            : (current + step + toplevels.length) % toplevels.length;
        toplevels[next].activate();
    }

    // Apps started from the dock or Launchpad that have no window yet, as
    // lowercased app ID -> start time, so their dock icon can bounce meanwhile.
    property var launching: ({})
    readonly property int launchTimeout: 15000

    function noteLaunch(appId) {
        if (!appId || root.hasWindows(appId)) return;
        const next = Object.assign({}, root.launching);
        next[appId.toLowerCase()] = Date.now();
        root.launching = next;
    }

    function isLaunching(appId) {
        return !!appId && (appId.toLowerCase() in root.launching);
    }

    function pruneLaunching() {
        const now = Date.now();
        const next = {};
        let changed = false;
        for (const id in root.launching) {
            if (now - root.launching[id] < root.launchTimeout && !root.hasWindows(id))
                next[id] = root.launching[id];
            else
                changed = true;
        }
        if (changed) root.launching = next;
    }

    Timer {
        interval: 500
        repeat: true
        running: Object.keys(root.launching).length > 0
        onTriggered: root.pruneLaunching()
    }

    property list<var> apps: {
        var map = new Map();

        // Pinned apps
        const pinnedApps = Config.options?.dock.pinnedApps ?? [];
        for (const appId of pinnedApps) {
            if (!map.has(appId.toLowerCase())) map.set(appId.toLowerCase(), ({
                pinned: true,
                toplevels: []
            }));
        }

        // Separator
        if (pinnedApps.length > 0) {
            map.set("SEPARATOR", { pinned: false, toplevels: [] });
        }

        // Ignored apps
        const ignoredRegexStrings = Config.options?.dock.ignoredAppRegexes ?? [];
        const ignoredRegexes = ignoredRegexStrings.map(pattern => new RegExp(pattern, "i"));
        // Open windows
        for (const toplevel of ToplevelManager.toplevels.values) {
            if (ignoredRegexes.some(re => re.test(toplevel.appId))) continue;
            if (!map.has(toplevel.appId.toLowerCase())) map.set(toplevel.appId.toLowerCase(), ({
                pinned: false,
                toplevels: []
            }));
            map.get(toplevel.appId.toLowerCase()).toplevels.push(toplevel);
        }

        var values = [];

        for (const [key, value] of map) {
            values.push(appEntryComp.createObject(null, { appId: key, toplevels: value.toplevels, pinned: value.pinned }));
        }

        return values;
    }

    component TaskbarAppEntry: QtObject {
        id: wrapper
        required property string appId
        required property list<var> toplevels
        required property bool pinned
    }
    Component {
        id: appEntryComp
        TaskbarAppEntry {}
    }
}