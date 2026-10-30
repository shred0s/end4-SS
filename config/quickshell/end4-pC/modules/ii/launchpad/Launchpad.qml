import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

/**
 * macOS-style Launchpad: a full-screen, paged grid of every installed app with
 * search, opened from the dock's left button.
 */
Scope {
    id: root

    readonly property int closeDuration: 200
    // Building the grid and decoding every icon takes a while, so the Launchpad
    // is built once in the background after startup and then only hidden.
    property bool warm: false

    Timer {
        running: true
        interval: 5000
        onTriggered: root.warm = true
    }

    Connections {
        target: GlobalStates
        function onLaunchpadOpenChanged() {
            if (GlobalStates.launchpadOpen) {
                if (GlobalStates.launchpadScreen === "")
                    GlobalStates.launchpadScreen = WM.focusedMonitor?.name ?? "";
                closeTimer.stop();
            } else {
                closeTimer.restart();
            }
        }
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) GlobalStates.launchpadOpen = false;
        }
    }

    // Keeps the window shown while the close animation plays.
    Timer {
        id: closeTimer
        interval: root.closeDuration
    }

    Loader {
        id: launchpadLoader
        active: root.warm || GlobalStates.launchpadOpen

        // While closed, the window isn't hidden but shrunk to a 1x1, click-through
        // pixel under everything. A hidden window falls back to the screen's
        // integer scale (2x instead of 1.67x on a fractionally scaled monitor),
        // and every scale change makes Qt re-render all the icons.
        sourceComponent: PanelWindow {
            id: launchpadWindow
            readonly property bool shown: GlobalStates.launchpadOpen || closeTimer.running
            // Stays on the last screen while closed; moving it re-lays out the grid.
            screen: Quickshell.screens.find(s => s.name === GlobalStates.launchpadScreen) ?? Quickshell.screens[0]

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:launchpad"
            WlrLayershell.layer: launchpadWindow.shown ? WlrLayer.Overlay : WlrLayer.Background
            WlrLayershell.keyboardFocus: GlobalStates.launchpadOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: "transparent"
            mask: launchpadWindow.shown ? null : noInput
            implicitWidth: 1
            implicitHeight: 1

            Region {
                id: noInput
            }

            anchors {
                top: true
                left: true
                bottom: launchpadWindow.shown
                right: launchpadWindow.shown
            }

            LaunchpadContent {
                // Sized from the screen, not the window, which is 1x1 while closed.
                width: launchpadWindow.screen?.width ?? 0
                height: launchpadWindow.screen?.height ?? 0
                shown: GlobalStates.launchpadOpen
                closeDuration: root.closeDuration
                onCloseRequested: GlobalStates.launchpadOpen = false
            }
        }
    }

    function open() {
        GlobalStates.launchpadScreen = WM.focusedMonitor?.name ?? GlobalStates.launchpadScreen;
        GlobalStates.launchpadOpen = true;
    }

    IpcHandler {
        target: "launchpad"

        function toggle(): void {
            if (GlobalStates.launchpadOpen) GlobalStates.launchpadOpen = false;
            else root.open();
        }

        function open(): void {
            root.open();
        }

        function close(): void {
            GlobalStates.launchpadOpen = false;
        }
    }

    CompositorGlobalShortcut {
        name: "launchpadToggle"
        description: "Toggles Launchpad on press"

        onPressed: {
            if (GlobalStates.launchpadOpen) GlobalStates.launchpadOpen = false;
            else root.open();
        }
    }
}
