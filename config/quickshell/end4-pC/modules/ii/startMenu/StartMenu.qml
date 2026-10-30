import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Windows-style start menu, opened by Super and the dock's launcher button
 * when Settings > Interface > Launcher is set to "Start menu".
 */
Scope {
    id: root

    readonly property int closeDuration: 220
    // Stays true until the close animation has played. Kept apart from the open
    // state: a binding on both would drop the window the moment it closes.
    property bool windowShown: false

    Connections {
        target: GlobalStates
        function onStartMenuOpenChanged() {
            if (GlobalStates.startMenuOpen) {
                closeTimer.stop();
                root.windowShown = true;
            } else {
                closeTimer.restart();
            }
        }
    }

    Timer {
        id: closeTimer
        interval: root.closeDuration
        onTriggered: root.windowShown = false
    }

    Loader {
        active: root.windowShown

        sourceComponent: PanelWindow {
            id: menuWindow
            screen: Quickshell.screens.find(s => s.name === GlobalStates.startMenuScreen) ?? Quickshell.screens[0]

            readonly property bool dock: Config.options.dock.enable
            readonly property string side: menuWindow.dock ? DockStyle.position : "bottom"
            readonly property real shadowMargin: Appearance.sizes.elevationMargin
            // From the screen edge to just past the dock (or the edge without one).
            // A pinned dock reserves its space already, and the menu respects that.
            readonly property real dockEdge: menuWindow.dock
                ? DockStyle.thickness - Appearance.sizes.elevationMargin - (DockStyle.flush ? Appearance.sizes.hyprlandGapsOut : 0)
                : 0
            readonly property real reserved: menuWindow.dock && GlobalStates.dockPinned ? DockStyle.zone : 0
            readonly property real edgeMargin: menuWindow.dockEdge + Appearance.sizes.hyprlandGapsOut * 2
                - menuWindow.reserved - menuWindow.shadowMargin

            WlrLayershell.namespace: "quickshell:startMenu"
            WlrLayershell.layer: WlrLayer.Overlay
            // Not Exclusive: an exclusive layer keeps Hyprland from ending the focus
            // grab, so clicks outside wouldn't close the menu. The grab gives it the keyboard.
            WlrLayershell.keyboardFocus: GlobalStates.startMenuOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: 0
            color: "transparent"

            // Next to the dock, centered along it
            anchors {
                bottom: menuWindow.side === "bottom"
                left: menuWindow.side === "left"
                right: menuWindow.side === "right"
            }
            margins {
                bottom: menuWindow.side === "bottom" ? menuWindow.edgeMargin : 0
                left: menuWindow.side === "left" ? menuWindow.edgeMargin : 0
                right: menuWindow.side === "right" ? menuWindow.edgeMargin : 0
            }
            implicitWidth: content.implicitWidth + menuWindow.shadowMargin * 2
            implicitHeight: content.implicitHeight + menuWindow.shadowMargin * 2

            // The shadow margin lets clicks through; they count as outside
            mask: Region {
                item: content
            }

            // Clicking anywhere outside closes the menu, on any screen
            HyprlandFocusGrab {
                active: GlobalStates.startMenuOpen
                windows: [menuWindow]
                onCleared: GlobalStates.startMenuOpen = false
            }

            StartMenuContent {
                id: content
                anchors.centerIn: parent
                width: implicitWidth
                height: implicitHeight
                side: menuWindow.side
                shown: GlobalStates.startMenuOpen
                closeDuration: root.closeDuration
                onCloseRequested: GlobalStates.startMenuOpen = false
            }
        }
    }

    IpcHandler {
        target: "startMenu"

        function toggle(): void {
            Launcher.toggle("");
        }

        function open(): void {
            Launcher.open("");
        }

        function close(): void {
            Launcher.close();
        }
    }

    // Opens whichever launcher is set in Settings (start menu or overview)
    CompositorGlobalShortcut {
        name: "launcherToggle"
        description: "Toggles the launcher (start menu or overview) on press"

        onPressed: Launcher.toggle("")
    }
}
