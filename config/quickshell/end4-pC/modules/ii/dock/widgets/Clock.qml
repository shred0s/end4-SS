import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Time with the date below; stacked hours and minutes on a side dock
DockWidgetButton {
    id: root
    popup: CalendarPopup {}
    wide: true
    tooltipText: Qt.locale().toString(DateTime.clock.date, "dddd d MMMM yyyy")

    contentItem: Item {
        implicitWidth: column.implicitWidth
        implicitHeight: column.implicitHeight

        ColumnLayout {
            id: column
            anchors.centerIn: parent
            spacing: -3

            StyledText {
                renderType: Text.CurveRendering
                visible: !DockStyle.vertical
                Layout.alignment: Qt.AlignHCenter
                text: DateTime.time
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
                color: root.contentColor
            }

            Repeater {
                model: DockStyle.vertical ? [DateTime.hourStr, DateTime.minuteStr] : []
                delegate: StyledText {
                    required property string modelData
                    Layout.alignment: Qt.AlignHCenter
                    text: modelData
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                    color: root.contentColor
                }
            }

            StyledText {
                renderType: Text.CurveRendering
                visible: Config.options.dock.widgets.clockShowDate
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 2
                text: DockStyle.vertical ? DateTime.shortDate : Qt.locale().toString(DateTime.clock.date, "ddd d MMM")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.contentColor
                opacity: 0.75
            }
        }
    }
}
