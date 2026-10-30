import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

Item {
    id: root
    required property var entry
    // A file:// URL decodes in the background; anything else loads on the UI thread.
    property string iconUrl: ""
    property real iconSize: 96
    property bool selected: false
    property bool showLabel: true
    // Hidden from the grid; only shown while searching.
    property bool dimmed: false

    signal clicked()
    signal menuRequested(real x, real y)

    Rectangle {
        id: highlight
        anchors.centerIn: tileColumn
        width: Math.min(root.width - 8, Math.max(tileColumn.width, root.iconSize) + 28)
        height: tileColumn.height + 22
        radius: Appearance.rounding.large
        color: ColorUtils.transparentize(Appearance.colors.colOnLayer0,
            root.selected ? 0.82 : mouseArea.containsMouse ? 0.92 : 1)
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    ColumnLayout {
        id: tileColumn
        anchors.centerIn: parent
        spacing: 8
        opacity: root.dimmed ? 0.45 : 1

        IconImage {
            Layout.alignment: Qt.AlignHCenter
            implicitSize: root.iconSize
            asynchronous: root.iconUrl.startsWith("file:")
            source: root.iconUrl
            scale: mouseArea.pressed ? 0.9 : 1
            Behavior on scale {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        StyledText {
            visible: root.showLabel
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: root.width - 16
            text: root.entry?.name ?? ""
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer0
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: highlight
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: event => {
            if (event.button === Qt.RightButton)
                root.menuRequested(event.x + highlight.x, event.y + highlight.y);
            else
                root.clicked();
        }
    }
}
