import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Title row of a dock popup: icon, title, subtitle and optional controls on the right
RowLayout {
    id: root
    property string icon
    property string title
    property string subtitle
    default property alias trailing: trailingRow.data

    spacing: 10

    Rectangle {
        implicitWidth: 38
        implicitHeight: 38
        radius: width / 2
        color: Appearance.colors.colPrimaryContainer
        MaterialSymbol {
            anchors.centerIn: parent
            text: root.icon
            iconSize: 21
            fill: 1
            color: Appearance.colors.colOnPrimaryContainer
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        StyledText {
            Layout.fillWidth: true
            text: root.title
            font.pixelSize: Appearance.font.pixelSize.large
            font.weight: Font.DemiBold
            color: Appearance.m3colors.m3onSurface
            elide: Text.ElideRight
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.subtitle !== ""
            text: root.subtitle
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
        }
    }

    RowLayout {
        id: trailingRow
        spacing: 6
    }
}
