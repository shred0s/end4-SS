import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

// A calendar app icon showing today's date
DockWidgetButton {
    id: root
    popup: CalendarPopup {}
    tooltipText: Qt.locale().toString(DateTime.clock.date, "dddd d MMMM yyyy")

    contentItem: Item {
        implicitWidth: tile.width
        implicitHeight: tile.height

        Rectangle {
            id: tile
            anchors.centerIn: parent
            width: DockStyle.iconSize
            height: DockStyle.iconSize
            radius: width * 0.23
            color: Appearance.m3colors.m3surfaceContainerHighest

            Column {
                anchors.centerIn: parent
                spacing: -2

                StyledText {
                    renderType: Text.CurveRendering
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.locale().toString(DateTime.clock.date, "ddd").toUpperCase()
                    font.pixelSize: Math.max(7, Math.round(tile.width * 0.24))
                    font.weight: Font.Bold
                    color: Appearance.colors.colError
                }

                StyledText {
                    renderType: Text.CurveRendering
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: DateTime.clock.date.getDate()
                    font.pixelSize: Math.round(tile.width * 0.5)
                    font.weight: Font.DemiBold
                    color: Appearance.m3colors.m3onSurface
                }
            }
        }
    }
}
