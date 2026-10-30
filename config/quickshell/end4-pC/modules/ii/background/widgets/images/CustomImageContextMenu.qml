import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/*
 * Right-click menu for a CustomImage desktop widget
 */
Item {
    id: root

    property bool hasImage: false
    property alias isOpen: menuLoader.active
    property rect anchorRect

    signal chooseImageRequested()
    signal clearImageRequested()
    signal addImageRequested()
    signal removeRequested()

    function open(item, x, y) {
        menuLoader.active = false;
        const pos = root.QsWindow.mapFromItem(item, x, y);
        root.anchorRect = Qt.rect(pos.x, pos.y, 1, 1);
        menuLoader.active = true;
    }

    function close() {
        menuLoader.active = false;
    }

    Loader {
        id: menuLoader
        active: false
        sourceComponent: PopupWindow {
            id: contextPopup
            visible: true

            anchor {
                window: root.QsWindow.window
                rect: root.anchorRect
                gravity: Edges.Bottom | Edges.Right
                edges: Edges.Top | Edges.Left
                adjustment: PopupAdjustment.All
            }

            HyprlandFocusGrab {
                active: true
                windows: [contextPopup]
                onCleared: root.close()
            }

            color: "transparent"
            mask: Region {
                item: menuBackground
            }
            implicitWidth: menuBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
            implicitHeight: menuBackground.implicitHeight + Appearance.sizes.elevationMargin * 2

            StyledRectangularShadow {
                target: menuBackground
            }

            Rectangle {
                id: menuBackground
                property real padding: 4

                anchors.centerIn: parent
                color: Config.options.appearance.uiBackground === "oled" ? "#000000" : Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.normal
                implicitWidth: menuColumn.implicitWidth + padding * 2
                implicitHeight: menuColumn.implicitHeight + padding * 2
                focus: true
                Keys.onEscapePressed: root.close()

                opacity: 0
                scale: 0.9
                Component.onCompleted: {
                    opacity = 1;
                    scale = 1;
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on scale {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }

                ColumnLayout {
                    id: menuColumn
                    anchors {
                        fill: parent
                        margins: parent.padding
                    }
                    spacing: 0

                    DockContextMenu.ContextMenuItem {
                        iconName: "folder_open"
                        label: Translation.tr("Choose image…")
                        onClicked: {
                            root.close();
                            root.chooseImageRequested();
                        }
                    }

                    DockContextMenu.ContextMenuItem {
                        visible: root.hasImage
                        iconName: "hide_image"
                        label: Translation.tr("Clear image")
                        onClicked: {
                            root.close();
                            root.clearImageRequested();
                        }
                    }

                    DockContextMenu.ContextMenuSeparator {}

                    DockContextMenu.ContextMenuItem {
                        iconName: "add_photo_alternate"
                        label: Translation.tr("Add another image")
                        onClicked: {
                            root.close();
                            root.addImageRequested();
                        }
                    }

                    DockContextMenu.ContextMenuItem {
                        iconName: "delete"
                        label: Translation.tr("Remove image widget")
                        onClicked: {
                            root.close();
                            root.removeRequested();
                        }
                    }

                    DockContextMenu.ContextMenuSeparator {}

                    DockContextMenu.ContextMenuItem {
                        iconName: Config.options.background.widgetsLocked ? "lock_open" : "lock"
                        label: Config.options.background.widgetsLocked
                            ? Translation.tr("Unlock widget positions")
                            : Translation.tr("Lock widget positions")
                        onClicked: {
                            root.close();
                            Config.options.background.widgetsLocked = !Config.options.background.widgetsLocked;
                        }
                    }
                }
            }
        }
    }
}
