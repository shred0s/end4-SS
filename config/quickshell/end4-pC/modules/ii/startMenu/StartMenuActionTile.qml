import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// A quick action in the start menu; toggles fill with the accent while on
RippleButton {
    id: root
    property string symbol
    property string label
    property bool active: false
    // Entrance progress while the menu opens
    property real reveal: 1

    opacity: root.reveal
    transform: Translate { y: (1 - root.reveal) * 16 }

    focusPolicy: Qt.NoFocus
    implicitHeight: 44
    horizontalPadding: 12
    buttonRadius: Appearance.rounding.normal
    colBackground: root.active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
    colBackgroundHover: root.active ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer1Hover
    colRipple: root.active ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer1Active

    contentItem: RowLayout {
        spacing: 10

        MaterialSymbol {
            text: root.symbol
            fill: root.active ? 1 : 0
            iconSize: 20
            color: root.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
        }

        StyledText {
            Layout.fillWidth: true
            text: root.label
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
        }
    }
}
