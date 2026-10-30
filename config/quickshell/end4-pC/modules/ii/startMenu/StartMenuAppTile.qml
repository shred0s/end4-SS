import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

// An app in the start menu's pinned grid: icon with its name below
RippleButton {
    id: root
    required property var entry
    property bool selected: false
    readonly property string iconUrl: Launcher.iconFor(root.entry)
    // Entrance progress while the menu opens; `pop` overshoots, for the icon
    property real reveal: 1
    property real pop: 1
    signal menuRequested(real x, real y)

    opacity: root.reveal
    transform: Translate { y: (1 - root.reveal) * 18 }

    focusPolicy: Qt.NoFocus
    topPadding: 12
    bottomPadding: 8
    horizontalPadding: 4
    buttonRadius: Appearance.rounding.normal
    colBackground: root.selected ? Appearance.colors.colSecondaryContainer : "transparent"
    colBackgroundHover: root.selected ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    altAction: event => root.menuRequested(event.x, event.y)

    contentItem: ColumnLayout {
        spacing: 7

        IconImage {
            Layout.alignment: Qt.AlignHCenter
            implicitSize: 36
            // A file decodes in the background; theme icons load on the UI thread
            asynchronous: root.iconUrl.startsWith("file:")
            source: root.iconUrl
            scale: (root.down ? 0.9 : 1) * (0.4 + 0.6 * root.pop)
            Behavior on scale {
                // Only for presses; the entrance pop is animated already
                enabled: root.pop === 1
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: root.entry?.name ?? ""
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0
        }
    }
}
