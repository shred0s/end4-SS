import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

// A row in the start menu's lists (all apps, search results, recent files)
RippleButton {
    id: root
    property string iconUrl: ""
    // Used when there's no icon file: a Material symbol, or a glyph like an emoji
    property string symbol: ""
    property string glyph: ""
    property color symbolColor: Appearance.colors.colOnLayer1
    property string title
    property string subtitle
    // Shown on the right while selected, e.g. "Open"
    property string verb
    property bool selected: false
    property real iconSize: 28
    // Entrance progress while the menu opens
    property real reveal: 1
    signal menuRequested(real x, real y)

    opacity: root.reveal
    transform: Translate { y: (1 - root.reveal) * 16 }

    focusPolicy: Qt.NoFocus
    implicitHeight: root.subtitle !== "" ? 48 : 42
    horizontalPadding: 10
    buttonRadius: Appearance.rounding.small
    colBackground: root.selected ? Appearance.colors.colSecondaryContainer : "transparent"
    colBackgroundHover: root.selected ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    altAction: event => root.menuRequested(event.x, event.y)

    contentItem: RowLayout {
        spacing: 12

        Item {
            implicitWidth: root.iconSize
            implicitHeight: root.iconSize

            IconImage {
                anchors.fill: parent
                visible: root.iconUrl !== ""
                asynchronous: root.iconUrl.startsWith("file:")
                source: root.iconUrl
            }

            // Symbols sit on a tinted square, like file icons
            Rectangle {
                anchors.fill: parent
                visible: root.iconUrl === "" && root.symbol !== ""
                radius: Appearance.rounding.verysmall
                color: Appearance.colors.colLayer2
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.symbol
                    iconSize: Math.round(root.iconSize * 0.68)
                    color: root.symbolColor
                }
            }

            StyledText {
                anchors.centerIn: parent
                visible: root.iconUrl === "" && root.symbol === ""
                text: root.glyph
                font.pixelSize: Math.round(root.iconSize * 0.75)
                color: Appearance.colors.colOnLayer1
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: -1

            StyledText {
                Layout.fillWidth: true
                text: root.title
                elide: Text.ElideRight
                maximumLineCount: 1
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.subtitle !== ""
                text: root.subtitle
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        StyledText {
            visible: root.selected && root.verb !== ""
            text: root.verb
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnSecondaryContainer
        }
    }
}
