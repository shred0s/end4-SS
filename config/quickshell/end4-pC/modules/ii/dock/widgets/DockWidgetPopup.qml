import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Hyprland

/**
 * Popup a dock widget opens instead of a window or sidebar. Opens away from the
 * screen edge the dock is on and closes on outside clicks or Escape.
 */
Item {
    id: root

    property Item button
    property Component content
    property alias isOpen: popupLoader.active
    property real closedAt: 0
    readonly property Item contentItem: popupLoader.item?.contentItem ?? null

    function open() {
        popupLoader.active = true;
    }

    function close() {
        if (!popupLoader.active) return;
        popupLoader.active = false;
        root.closedAt = Date.now();
    }

    // Clicking the button while open clears the focus grab first, so don't reopen
    function toggle() {
        if (root.isOpen)
            root.close();
        else if (Date.now() - root.closedAt > 300)
            root.open();
    }

    Loader {
        id: popupLoader
        active: false
        sourceComponent: PopupWindow {
            id: popupWindow
            readonly property Item contentItem: contentLoader.item
            readonly property int side: DockStyle.position === "left" ? Edges.Right
                : DockStyle.position === "right" ? Edges.Left
                : Edges.Top
            readonly property real margin: Appearance.sizes.elevationMargin

            visible: true
            color: "transparent"
            anchor {
                item: root.button
                edges: popupWindow.side
                gravity: popupWindow.side
                adjustment: PopupAdjustment.Slide
            }
            // Clicks on the transparent shadow margin count as outside
            mask: Region {
                item: popupBackground
            }
            implicitWidth: popupBackground.implicitWidth + popupWindow.margin * 2
            implicitHeight: popupBackground.implicitHeight + popupWindow.margin * 2

            HyprlandFocusGrab {
                active: true
                windows: [popupWindow]
                onCleared: root.close()
            }

            StyledRectangularShadow {
                target: popupBackground
                opacity: popupBackground.opacity
            }

            Rectangle {
                id: popupBackground
                readonly property real padding: 14
                anchors.centerIn: parent
                implicitWidth: contentLoader.implicitWidth + padding * 2
                implicitHeight: contentLoader.implicitHeight + padding * 2
                color: Config.options.appearance.uiBackground === "oled" ? "#000000" : Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.large
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                focus: true

                // Grows out of the dock
                opacity: 0
                scale: 0.94
                transformOrigin: popupWindow.side === Edges.Right ? Item.Left : popupWindow.side === Edges.Left ? Item.Right : Item.Bottom
                Component.onCompleted: {
                    opacity = 1;
                    scale = 1;
                }
                Behavior on opacity {
                    NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                }

                Keys.onEscapePressed: root.close()

                Loader {
                    id: contentLoader
                    anchors.centerIn: parent
                    width: implicitWidth
                    height: implicitHeight
                    focus: true
                    sourceComponent: root.content
                }
            }
        }
    }
}
