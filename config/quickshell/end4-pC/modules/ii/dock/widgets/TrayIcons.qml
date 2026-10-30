pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.bar
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Widgets

// System tray: click activates, middle-click is the secondary action, right-click opens the menu
DockWidgetButton {
    id: root
    wide: true
    // Has its own buttons inside; don't zoom the whole row
    scaleContent: false
    available: root.items.length > 0
    colBackgroundHover: root.material ? root.tone : "transparent"
    rippleEnabled: false
    holdOpen: root.activeMenu !== null

    readonly property var items: TrayService.pinnedItems.concat(TrayService.unpinnedItems)
    readonly property real iconSize: Math.round(DockStyle.iconSize * 0.58)
    property var activeMenu: null
    readonly property int menuEdge: DockStyle.position === "left" ? Edges.Right
        : DockStyle.position === "right" ? Edges.Left
        : Edges.Top

    HyprlandFocusGrab {
        id: focusGrab
        active: root.activeMenu !== null
        windows: [root.activeMenu]
        onCleared: root.activeMenu?.close()
    }

    contentItem: Item {
        implicitWidth: grid.implicitWidth
        implicitHeight: grid.implicitHeight

        GridLayout {
            id: grid
            anchors.centerIn: parent
            columns: DockStyle.vertical ? 1 : -1
            columnSpacing: 2
            rowSpacing: 2

            Repeater {
                model: ScriptModel { values: root.items }
                delegate: MouseArea {
                    id: trayItem
                    required property SystemTrayItem modelData
                    implicitWidth: root.iconSize + 8
                    implicitHeight: root.iconSize + 8
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor

                    onClicked: event => {
                        if (event.button === Qt.LeftButton) {
                            trayItem.modelData.activate();
                        } else if (event.button === Qt.MiddleButton) {
                            trayItem.modelData.secondaryActivate();
                        } else if (trayItem.modelData.hasMenu) {
                            if (menuLoader.item) menuLoader.item.close();
                            else menuLoader.active = true;
                        }
                    }
                    onWheel: event => trayItem.modelData.scroll(event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x, event.angleDelta.y === 0)

                    Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.small
                        color: trayItem.containsMouse ? (root.material ? ColorUtils.mix(root.tone, root.toneContent, 0.85) : Appearance.colors.colLayer1Hover) : "transparent"
                    }

                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: root.iconSize
                        source: trayItem.modelData.icon
                        scale: trayItem.pressed ? 0.88 : 1
                    }

                    PopupToolTip {
                        text: TrayService.getTooltipForItem(trayItem.modelData)
                        extraVisibleCondition: trayItem.containsMouse && menuLoader.item === null && text !== ""
                        alternativeVisibleCondition: extraVisibleCondition
                        verticalMargin: 8
                        anchorEdges: root.menuEdge
                    }

                    Loader {
                        id: menuLoader
                        active: false
                        sourceComponent: SysTrayMenu {
                            Component.onCompleted: this.open()
                            trayItemMenuHandle: trayItem.modelData.menu
                            trayItemId: trayItem.modelData.id
                            anchor {
                                window: trayItem.QsWindow.window
                                item: trayItem
                                gravity: root.menuEdge
                                edges: root.menuEdge
                            }
                            onMenuOpened: window => root.activeMenu = window
                            onMenuClosed: {
                                root.activeMenu = null;
                                menuLoader.active = false;
                            }
                        }
                    }
                }
            }
        }
    }
}
