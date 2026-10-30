import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

RippleButton {
    id: menuItemRoot
    property string iconName
    // Themed icon; falls back to iconName (a Material Symbol) when empty.
    property string iconSource
    property string label
    property color contentColor: enabled ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3outline
    Layout.fillWidth: true
    implicitHeight: 36
    implicitWidth: Math.max(itemRow.implicitWidth + itemRow.anchors.leftMargin + itemRow.anchors.rightMargin, 180)
    buttonRadius: Appearance.rounding.small

    contentItem: RowLayout {
        id: itemRow
        anchors {
            fill: parent
            leftMargin: 10
            rightMargin: 14
        }
        spacing: 8

        IconImage {
            visible: menuItemRoot.iconSource !== ""
            source: menuItemRoot.iconSource
            implicitSize: Appearance.font.pixelSize.normal
            Layout.alignment: Qt.AlignVCenter
        }

        MaterialSymbol {
            text: menuItemRoot.iconName
            iconSize: Appearance.font.pixelSize.normal
            color: menuItemRoot.contentColor
            visible: menuItemRoot.iconSource === "" && menuItemRoot.iconName !== ""
            Layout.alignment: Qt.AlignVCenter
        }

        StyledText {
            Layout.fillWidth: true
            text: menuItemRoot.label
            horizontalAlignment: Text.AlignLeft
            font.pixelSize: Appearance.font.pixelSize.small
            color: menuItemRoot.contentColor
            elide: Text.ElideRight
        }
    }
}
