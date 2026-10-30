import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets

/**
 * macOS-style stack: the newest files in Downloads fan out of the dock in an
 * arc. Scroll for older ones, click to open, right-click for more.
 */
Item {
    id: root

    property alias isOpen: popupLoader.active
    property real closedAt: 0
    property var items: []
    property string folder: ""
    property bool loading: false
    // Point the fan's window hangs from, in dock-window coordinates
    property point origin
    // Which way the arc bends (+1 right) and which side the names go on
    property int bend: 1
    property int labelSide: -1

    readonly property int maxShown: 9
    readonly property real iconSize: 50
    readonly property real step: 58
    readonly property real pad: 14
    readonly property real labelWidth: 240
    readonly property real labelGap: 10
    // Room the arc and the names need on each side of the first file's centre
    readonly property real curveMax: root.curve(root.maxShown + 0.15)
    readonly property real leftExtent: root.pad + root.iconSize / 2
        + (root.labelSide < 0 ? root.labelGap + root.labelWidth : 0) + (root.bend < 0 ? root.curveMax : 0)
    readonly property real rightExtent: root.pad + root.iconSize / 2
        + (root.labelSide > 0 ? root.labelGap + root.labelWidth : 0) + (root.bend > 0 ? root.curveMax : 0)

    // Sideways bend of the slot p places up the fan
    function curve(p) {
        return 1.15 * p * p + 2 * p;
    }

    function open(button) {
        const topLeft = root.QsWindow.mapFromItem(button, 0, 0);
        const centerX = topLeft.x + button.width / 2;
        const centerY = topLeft.y + button.height / 2;
        const reach = root.pad + root.iconSize / 2;
        if (DockStyle.position === "left") {
            // Beside the dock, bending away from it
            root.bend = 1;
            root.labelSide = 1;
            root.origin = Qt.point(topLeft.x + button.width, centerY + reach);
        } else if (DockStyle.position === "right") {
            root.bend = -1;
            root.labelSide = -1;
            root.origin = Qt.point(topLeft.x, centerY + reach);
        } else {
            // Like macOS: rising from the icon and bending right, names on the left
            root.bend = 1;
            root.labelSide = -1;
            root.origin = Qt.point(centerX - root.leftExtent, topLeft.y);
        }
        root.refresh();
        popupLoader.active = true;
    }

    function close() {
        if (!popupLoader.active) return;
        popupLoader.active = false;
        root.closedAt = Date.now();
    }

    // Clicking the button while open clears the focus grab first, so don't reopen
    function toggle(button) {
        if (root.isOpen)
            root.close();
        else if (Date.now() - root.closedAt > 300)
            root.open(button);
    }

    // Moves through the files, e.g. from the wheel over the dock icon
    function scroll(steps) {
        popupLoader.item?.scrollBy(steps);
    }

    function refresh() {
        root.loading = true;
        lister.command = ["python3", Quickshell.shellPath("scripts/dock/recent_files.py"), Config.options.dock.widgets.downloadsFolder ?? "", "80"];
        lister.running = true;
    }

    function fileUrl(path) {
        return "file://" + path.split("/").map(part => encodeURIComponent(part)).join("/");
    }

    function openItem(item) {
        Quickshell.execDetached(["xdg-open", item.path]);
        root.close();
    }

    function showInFolder(item) {
        Quickshell.execDetached(["bash", "-c",
            'dbus-send --session --print-reply --dest=org.freedesktop.FileManager1 /org/freedesktop/FileManager1 org.freedesktop.FileManager1.ShowItems array:string:"$1" string:"" >/dev/null 2>&1 || xdg-open "$2"',
            "_", root.fileUrl(item.path), root.folder]);
        root.close();
    }

    function trashItem(item) {
        trasher.command = ["gio", "trash", "--", item.path];
        trasher.running = true;
    }

    Process {
        id: lister
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.folder = data.folder;
                    root.items = data.items;
                } catch (e) {
                    console.warn("[DownloadsFan] Could not list the folder:", e);
                }
                root.loading = false;
            }
        }
    }

    Process {
        id: trasher
        onExited: {
            root.refresh();
            Trash.refresh();
        }
    }

    Loader {
        id: popupLoader
        active: false
        sourceComponent: PopupWindow {
            id: fanWindow
            visible: true

            readonly property int count: root.items.length
            readonly property int shown: Math.max(1, Math.min(count, root.maxShown))
            readonly property real maxScroll: Math.max(0, count - root.maxShown)
            property real scrollTarget: 0
            property real scroll: scrollTarget
            Behavior on scroll {
                NumberAnimation {
                    duration: 220
                    easing.type: Easing.OutCubic
                }
            }
            property real progress: 0
            NumberAnimation on progress {
                from: 0
                to: 1
                duration: 320
                easing.type: Easing.OutBack
                easing.overshoot: 1.2
            }

            // Where slot p sits, relative to the first slot's centre
            function slotX(p) {
                return root.bend * root.curve(Math.max(0, p)) * fanWindow.progress;
            }
            function tilt(p) {
                return root.bend * Math.max(0, p) * 1.1 * fanWindow.progress;
            }
            function slotY(p) {
                return -p * root.step * fanWindow.progress;
            }

            readonly property real headerSlot: shown + 0.15
            implicitWidth: root.leftExtent + root.rightExtent
            implicitHeight: root.pad * 2 + root.iconSize + headerSlot * root.step
            // Centre of the first slot, in this window
            readonly property real baseX: root.leftExtent
            readonly property real baseY: implicitHeight - root.pad - root.iconSize / 2

            anchor {
                window: root.QsWindow.window
                rect: Qt.rect(root.origin.x, root.origin.y, 1, 1)
                edges: Edges.Top | Edges.Left
                gravity: Edges.Top | (DockStyle.position === "right" ? Edges.Left : Edges.Right)
                adjustment: PopupAdjustment.Slide
            }
            color: "transparent"

            HyprlandFocusGrab {
                active: true
                windows: [fanWindow]
                onCleared: root.close()
            }

            function scrollBy(steps) {
                fanWindow.scrollTarget = Math.max(0, Math.min(fanWindow.maxScroll, Math.round(fanWindow.scrollTarget + steps)));
            }

            Item {
                id: content
                anchors.fill: parent
                focus: true

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        if (itemMenu.item !== null) itemMenu.item = null;
                        else root.close();
                    } else if (event.key === Qt.Key_Up) {
                        fanWindow.scrollBy(1);
                    } else if (event.key === Qt.Key_Down) {
                        fanWindow.scrollBy(-1);
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                // Empty space closes the fan
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    onPressed: root.close()
                }

                property real wheelAccumulator: 0
                WheelHandler {
                    target: null
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => {
                        content.wheelAccumulator += event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                        while (Math.abs(content.wheelAccumulator) >= 120) {
                            const direction = content.wheelAccumulator > 0 ? 1 : -1;
                            content.wheelAccumulator -= direction * 120;
                            fanWindow.scrollBy(direction);
                        }
                    }
                }

                // Header: open the folder, and where in the list the fan is
                Item {
                    id: header
                    readonly property real slot: fanWindow.headerSlot
                    // Lined up with the files' icon edge on the names' side
                    readonly property real iconEdge: fanWindow.baseX + fanWindow.slotX(slot) + root.labelSide * root.iconSize / 2
                    x: root.labelSide < 0 ? iconEdge - width + root.iconSize : iconEdge - root.iconSize
                    y: fanWindow.baseY + fanWindow.slotY(slot) - height / 2
                    width: headerButton.implicitWidth + 4
                    height: headerButton.implicitHeight + 4
                    opacity: Math.min(1, fanWindow.progress * 1.5)
                    transform: Rotation {
                        origin.x: root.labelSide < 0 ? header.width : 0
                        origin.y: header.height / 2
                        angle: fanWindow.tilt(header.slot)
                    }
                    // Drawn flat, then turned as one smooth texture
                    layer.enabled: true
                    layer.smooth: true
                    antialiasing: true

                    RippleButton {
                        id: headerButton
                        anchors.centerIn: parent
                        implicitHeight: 38
                        horizontalPadding: 14
                        buttonRadius: height / 2
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colRipple: Appearance.colors.colPrimaryActive
                        onClicked: {
                            Quickshell.execDetached(["xdg-open", root.folder]);
                            root.close();
                        }
                        contentItem: RowLayout {
                            spacing: 6
                            MaterialSymbol {
                                text: "folder_open"
                                iconSize: 18
                                fill: 1
                                color: Appearance.colors.colOnPrimary
                            }
                            StyledText {
                                text: {
                                    const name = root.folder.split("/").pop() || Translation.tr("Downloads");
                                    if (fanWindow.count === 0) return root.loading ? name : Translation.tr("%1 is empty").arg(name);
                                    if (fanWindow.count <= root.maxShown) return name;
                                    const first = Math.round(fanWindow.scrollTarget) + 1;
                                    return `${name} · ${first}–${Math.min(fanWindow.count, first + root.maxShown - 1)} / ${fanWindow.count}`;
                                }
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimary
                            }
                            MaterialSymbol {
                                visible: fanWindow.count > root.maxShown
                                text: "swap_vert"
                                iconSize: 16
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }
                }

                Repeater {
                    model: root.items
                    delegate: Item {
                        id: entry
                        required property var modelData
                        required property int index
                        // Slot along the fan; scrolling slides the files along the arc
                        readonly property real p: entry.index - fanWindow.scroll
                        readonly property real fade: Math.max(0, Math.min(1, 1 - Math.max(-entry.p, entry.p - (root.maxShown - 1)) * 1.6))
                        readonly property bool hovered: entryArea.containsMouse || itemMenu.item === entry.modelData
                        readonly property real margin: 4
                        readonly property real iconCenterX: root.labelSide < 0 ? entry.width - entry.margin - root.iconSize / 2 : entry.margin + root.iconSize / 2

                        visible: entry.fade > 0
                        width: root.iconSize + root.labelGap + root.labelWidth + entry.margin * 2
                        height: root.iconSize + entry.margin * 2
                        x: fanWindow.baseX + fanWindow.slotX(entry.p) - entry.iconCenterX
                        y: fanWindow.baseY + fanWindow.slotY(entry.p) - entry.height / 2
                        opacity: entry.fade * Math.min(1, fanWindow.progress * 1.5)
                        transform: Rotation {
                            origin.x: entry.iconCenterX
                            origin.y: entry.height / 2
                            angle: fanWindow.tilt(entry.p)
                        }
                        z: entry.hovered ? 2 : 1
                        // Drawn flat, then turned as one smooth texture; the margin keeps its edges soft
                        layer.enabled: true
                        layer.smooth: true
                        antialiasing: true

                        Item {
                            id: iconBox
                            x: entry.iconCenterX - root.iconSize / 2
                            y: entry.margin
                            width: root.iconSize
                            height: root.iconSize
                            scale: entry.hovered ? 1.08 : 1
                            Behavior on scale {
                                NumberAnimation { duration: 120 }
                            }

                            // Thumbnail for pictures, file-type icon for the rest
                            Image {
                                id: thumbnail
                                anchors.fill: parent
                                visible: entry.modelData.image && status === Image.Ready
                                asynchronous: true
                                fillMode: Image.PreserveAspectFit
                                sourceSize.width: root.iconSize * 2
                                sourceSize.height: root.iconSize * 2
                                source: entry.modelData.image ? root.fileUrl(entry.modelData.path) : ""
                                smooth: true
                                mipmap: true
                            }

                            IconImage {
                                anchors.fill: parent
                                visible: !thumbnail.visible
                                source: SystemAppearance.iconPath(entry.modelData.icon, entry.modelData.fallback)
                            }
                        }

                        Rectangle {
                            id: label
                            anchors.verticalCenter: parent.verticalCenter
                            x: root.labelSide > 0 ? iconBox.x + root.iconSize + root.labelGap : iconBox.x - root.labelGap - width
                            width: Math.min(root.labelWidth, labelText.implicitWidth + 22)
                            height: 26
                            radius: height / 2
                            color: entry.hovered ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.m3colors.m3surfaceContainerHighest, 0.08)
                            Behavior on color {
                                ColorAnimation { duration: 120 }
                            }

                            StyledText {
                                id: labelText
                                anchors.centerIn: parent
                                width: Math.min(implicitWidth, root.labelWidth - 22)
                                elide: Text.ElideMiddle
                                text: entry.modelData.name
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: entry.hovered ? Appearance.colors.colOnPrimary : Appearance.m3colors.m3onSurface
                            }
                        }

                        MouseArea {
                            id: entryArea
                            // Icon and name
                            x: root.labelSide > 0 ? iconBox.x : label.x
                            width: root.iconSize + root.labelGap + label.width
                            height: parent.height
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton)
                                    itemMenu.openAt(entryArea, mouse.x, mouse.y, entry.modelData);
                                else if (mouse.button === Qt.MiddleButton)
                                    root.showInFolder(entry.modelData);
                                else
                                    root.openItem(entry.modelData);
                            }
                        }
                    }
                }

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
                    z: 10

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
                                onClicked: root.openItem(itemMenu.item)
                            }
                            ContextMenuItem {
                                iconName: "folder_open"
                                label: Translation.tr("Show in folder")
                                onClicked: root.showInFolder(itemMenu.item)
                            }
                            ContextMenuSeparator {}
                            ContextMenuItem {
                                iconName: "content_copy"
                                label: Translation.tr("Copy")
                                onClicked: {
                                    Quickshell.execDetached(["wl-copy", "--type", "text/uri-list", root.fileUrl(itemMenu.item.path)]);
                                    itemMenu.item = null;
                                }
                            }
                            ContextMenuItem {
                                iconName: "link"
                                label: Translation.tr("Copy path")
                                onClicked: {
                                    Quickshell.execDetached(["wl-copy", itemMenu.item.path]);
                                    itemMenu.item = null;
                                }
                            }
                            ContextMenuSeparator {}
                            ContextMenuItem {
                                iconName: "delete"
                                label: Translation.tr("Move to Trash")
                                contentColor: Appearance.colors.colError
                                onClicked: {
                                    root.trashItem(itemMenu.item);
                                    itemMenu.item = null;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
