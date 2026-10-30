import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets

/**
 * Trash viewer that opens from the dock's trash button: lists trashed files with
 * where they came from, and restores or permanently deletes them.
 */
Item {
    id: root

    property alias isOpen: popupLoader.active
    // Button geometry in dock-window coordinates, captured on open.
    property rect anchorRect
    property real closedAt: 0

    function open(button) {
        const topLeft = root.QsWindow.mapFromItem(button, 0, 0);
        root.anchorRect = Qt.rect(topLeft.x, topLeft.y, button.width, button.height);
        Trash.lastError = "";
        Trash.refresh();
        popupLoader.active = true;
    }

    function close() {
        if (!popupLoader.active) return;
        popupLoader.active = false;
        root.closedAt = Date.now();
    }

    // Clicking the trash button while the popup is open clears the focus grab
    // (closing it) before the click lands, so don't let that click reopen it.
    function toggle(button) {
        if (root.isOpen)
            root.close();
        else if (Date.now() - root.closedAt > 300)
            root.open(button);
    }

    function openTrashFolder() {
        Quickshell.execDetached(["bash", "-c", "command -v dolphin >/dev/null && exec dolphin trash:/ || exec gio open trash:///"]);
        root.close();
    }

    Loader {
        id: popupLoader
        active: false
        sourceComponent: PopupWindow {
            id: trashPopup
            visible: true

            // Open away from the screen edge the dock is attached to.
            readonly property int side: DockStyle.position === "left" ? Edges.Right
                : DockStyle.position === "right" ? Edges.Left
                : Edges.Top

            // {title, ids} for a pending permanent delete; ids is null for "empty all".
            property var confirmation: null
            property string filter: ""
            readonly property var shownItems: {
                const query = trashPopup.filter.trim().toLowerCase();
                if (query === "") return Trash.items;
                return Trash.items.filter(item => item.name.toLowerCase().includes(query)
                    || item.origDir.toLowerCase().includes(query));
            }

            function askDelete(item) {
                trashPopup.confirmation = {
                    title: Translation.tr("Permanently delete “%1”?").arg(item.name),
                    ids: [item.id]
                };
            }

            function confirm() {
                const pending = trashPopup.confirmation;
                trashPopup.confirmation = null;
                if (!pending) return;
                if (pending.ids === null)
                    Trash.empty();
                else
                    Trash.remove(pending.ids);
            }

            anchor {
                window: root.QsWindow.window
                rect: root.anchorRect
                gravity: trashPopup.side
                edges: trashPopup.side
                adjustment: DockStyle.vertical ? PopupAdjustment.SlideY : PopupAdjustment.SlideX
            }

            HyprlandFocusGrab {
                active: true
                windows: [trashPopup]
                onCleared: root.close()
            }

            color: "transparent"
            // Clicks on the transparent shadow margin should count as outside.
            mask: Region {
                item: popupBackground
            }
            implicitWidth: popupBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
            implicitHeight: popupBackground.implicitHeight + Appearance.sizes.elevationMargin * 2

            StyledRectangularShadow {
                target: popupBackground
            }

            Rectangle {
                id: popupBackground
                readonly property real padding: 12

                anchors.centerIn: parent
                color: Config.options.appearance.uiBackground === "oled" ? "#000000" : Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.large
                implicitWidth: 460
                implicitHeight: contentColumn.implicitHeight + padding * 2
                focus: true

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        if (itemMenu.item !== null)
                            itemMenu.item = null;
                        else if (trashPopup.confirmation !== null)
                            trashPopup.confirmation = null;
                        else
                            root.close();
                        event.accepted = true;
                    } else if (filterField.visible && event.text.length > 0 && !filterField.activeFocus) {
                        filterField.forceActiveFocus();
                        filterField.insert(filterField.cursorPosition, event.text);
                        event.accepted = true;
                    }
                }

                opacity: 0
                transform: Scale {
                    id: popupScale
                    origin.x: trashPopup.side === Edges.Right ? 0 : trashPopup.side === Edges.Left ? popupBackground.width : popupBackground.width / 2
                    origin.y: trashPopup.side === Edges.Top ? popupBackground.height : popupBackground.height / 2
                    xScale: 0.9
                    yScale: 0.9
                }

                Component.onCompleted: openAnim.start()

                ParallelAnimation {
                    id: openAnim
                    NumberAnimation {
                        target: popupScale
                        properties: "xScale,yScale"
                        to: 1
                        duration: Appearance.animationCurves.expressiveDefaultSpatialDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                    }
                    NumberAnimation {
                        target: popupBackground
                        property: "opacity"
                        to: 1
                        duration: Appearance.animationCurves.expressiveEffectsDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                    }
                }

                ColumnLayout {
                    id: contentColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: popupBackground.padding
                    }
                    spacing: 10

                    // Header
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        spacing: 10

                        IconImage {
                            source: SystemAppearance.iconPath(Trash.count > 0 ? "user-trash-full" : "user-trash", "user-trash")
                            implicitSize: 36
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Trash")
                                font {
                                    family: Appearance.font.family.title
                                    pixelSize: Appearance.font.pixelSize.larger
                                    variableAxes: Appearance.font.variableAxes.title
                                }
                                color: Appearance.colors.colOnLayer2
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Trash.count === 0
                                    ? Translation.tr("No items")
                                    : (Trash.count === 1 ? Translation.tr("1 item") : Translation.tr("%1 items").arg(Trash.count))
                                        + " · " + Trash.formatSize(Trash.totalSize)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }

                        HeaderButton {
                            iconName: "folder_open"
                            tooltipText: Translation.tr("Open in file manager")
                            onClicked: root.openTrashFolder()
                        }

                        HeaderButton {
                            iconName: "delete_sweep"
                            label: Translation.tr("Empty")
                            enabled: Trash.count > 0 && !Trash.busy
                            onClicked: trashPopup.confirmation = {
                                title: Translation.tr("Permanently delete all %1 items?").arg(Trash.count),
                                ids: null
                            }
                        }
                    }

                    ToolbarTextField {
                        id: filterField
                        visible: Trash.count > 6
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        implicitHeight: 38
                        placeholderText: Translation.tr("Filter by name or folder")
                        colBackground: Appearance.colors.colLayer1
                        onTextChanged: trashPopup.filter = text
                        Keys.onEscapePressed: event => {
                            if (text.length > 0) {
                                text = "";
                                event.accepted = true;
                            } else {
                                event.accepted = false;
                            }
                        }
                    }

                    // Item list
                    StyledListView {
                        id: itemList
                        visible: trashPopup.shownItems.length > 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(contentHeight, 380)
                        clip: true
                        spacing: 2
                        popin: false
                        model: ScriptModel {
                            values: trashPopup.shownItems
                            objectProp: "id"
                        }
                        delegate: TrashItemRow {
                            id: itemRow
                            required property var modelData
                            item: modelData
                            width: itemList.width
                            onRestoreRequested: Trash.restore([modelData.id])
                            onDeleteRequested: trashPopup.askDelete(modelData)
                            onMenuRequested: (x, y) => itemMenu.openAt(itemRow, x, y, modelData)
                        }
                    }

                    // Empty and no-match states
                    ColumnLayout {
                        visible: Trash.loaded && trashPopup.shownItems.length === 0
                        Layout.fillWidth: true
                        Layout.topMargin: 18
                        Layout.bottomMargin: 22
                        spacing: 4

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: Trash.count === 0 ? "delete" : "search_off"
                            iconSize: 44
                            color: Appearance.colors.colSubtext
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Trash.count === 0 ? Translation.tr("Trash is empty") : Translation.tr("Nothing matches")
                            color: Appearance.colors.colSubtext
                        }
                    }

                    // Confirmation for permanent deletes
                    MessageBar {
                        visible: trashPopup.confirmation !== null
                        title: trashPopup.confirmation?.title ?? ""
                        body: Translation.tr("This can’t be undone.")

                        DialogButton {
                            buttonText: Translation.tr("Cancel")
                            onClicked: trashPopup.confirmation = null
                        }
                        DialogButton {
                            buttonText: Translation.tr("Delete")
                            colText: Appearance.colors.colError
                            onClicked: trashPopup.confirm()
                        }
                    }

                    MessageBar {
                        visible: trashPopup.confirmation === null && Trash.lastError !== ""
                        title: Translation.tr("Something went wrong")
                        body: Trash.lastError

                        DialogButton {
                            buttonText: Translation.tr("Dismiss")
                            onClicked: Trash.lastError = ""
                        }
                    }
                }

                // Right-click menu for an item
                Item {
                    id: itemMenu
                    property var item: null
                    property point anchorPoint

                    function openAt(source, x, y, item) {
                        itemMenu.anchorPoint = source.mapToItem(itemMenu, x, y);
                        itemMenu.item = item;
                    }

                    anchors.fill: parent
                    visible: item !== null

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.AllButtons
                        onPressed: itemMenu.item = null
                    }

                    StyledRectangularShadow {
                        target: menuBox
                    }

                    Rectangle {
                        id: menuBox
                        x: Math.max(6, Math.min(itemMenu.anchorPoint.x, itemMenu.width - width - 6))
                        y: Math.max(6, Math.min(itemMenu.anchorPoint.y, itemMenu.height - height - 6))
                        color: Appearance.m3colors.m3surfaceContainerHigh
                        radius: Appearance.rounding.normal
                        implicitWidth: menuColumn.implicitWidth + 8
                        implicitHeight: menuColumn.implicitHeight + 8

                        ColumnLayout {
                            id: menuColumn
                            anchors {
                                fill: parent
                                margins: 4
                            }
                            spacing: 0

                            ContextMenuItem {
                                iconName: "open_in_new"
                                label: Translation.tr("Open")
                                onClicked: {
                                    Quickshell.execDetached(["xdg-open", itemMenu.item.path]);
                                    itemMenu.item = null;
                                    root.close();
                                }
                            }
                            ContextMenuItem {
                                iconName: "folder"
                                label: Translation.tr("Open original folder")
                                enabled: (itemMenu.item?.origDir ?? "") !== ""
                                onClicked: {
                                    Quickshell.execDetached(["xdg-open", itemMenu.item.origDir]);
                                    itemMenu.item = null;
                                    root.close();
                                }
                            }
                            ContextMenuSeparator {}
                            ContextMenuItem {
                                iconName: "restore_from_trash"
                                label: Translation.tr("Put back")
                                onClicked: {
                                    Trash.restore([itemMenu.item.id]);
                                    itemMenu.item = null;
                                }
                            }
                            ContextMenuItem {
                                iconName: "delete_forever"
                                label: Translation.tr("Delete permanently")
                                contentColor: Appearance.colors.colError
                                onClicked: {
                                    trashPopup.askDelete(itemMenu.item);
                                    itemMenu.item = null;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    component HeaderButton: RippleButton {
        id: headerButton
        property string iconName
        property string label: ""
        property string tooltipText: ""
        implicitHeight: 36
        implicitWidth: label === "" ? 36 : headerRow.implicitWidth + 24
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active

        contentItem: Item {
            RowLayout {
                id: headerRow
                anchors.centerIn: parent
                spacing: 6
                MaterialSymbol {
                    text: headerButton.iconName
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    visible: headerButton.label !== ""
                    text: headerButton.label
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer2
                }
            }
        }

        StyledToolTip {
            text: headerButton.tooltipText
            extraVisibleCondition: headerButton.tooltipText !== ""
        }
    }

    component MessageBar: Rectangle {
        id: messageBar
        property string title
        property string body
        default property alias buttons: buttonRow.data
        Layout.fillWidth: true
        implicitHeight: messageColumn.implicitHeight + 20
        radius: Appearance.rounding.normal
        color: Appearance.colors.colErrorContainer

        ColumnLayout {
            id: messageColumn
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 14
                rightMargin: 8
            }
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                Layout.rightMargin: 6
                text: messageBar.title
                elide: Text.ElideMiddle
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnErrorContainer
            }
            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    text: messageBar.body
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnErrorContainer
                    opacity: 0.8
                }
                RowLayout {
                    id: buttonRow
                    spacing: 0
                }
            }
        }
    }
}
