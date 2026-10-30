import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// Control Center style tile: round icon, name and state; filled while on
RippleButton {
    id: root
    property string symbol
    property string label
    property string detail
    property bool active: false

    Layout.fillWidth: true
    implicitHeight: 58
    horizontalPadding: 10
    buttonRadius: Appearance.rounding.normal
    colBackground: root.active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
    colBackgroundHover: root.active ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover

    contentItem: RowLayout {
        spacing: 10
        Rectangle {
            implicitWidth: 34
            implicitHeight: 34
            radius: width / 2
            color: root.active ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
            MaterialSymbol {
                anchors.centerIn: parent
                text: root.symbol
                iconSize: 19
                fill: root.active ? 1 : 0
                color: root.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: -1
            StyledText {
                Layout.fillWidth: true
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                color: root.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.detail !== ""
                text: root.detail
                font.pixelSize: Appearance.font.pixelSize.smaller
                elide: Text.ElideRight
                color: root.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                opacity: 0.8
            }
        }
    }
}
