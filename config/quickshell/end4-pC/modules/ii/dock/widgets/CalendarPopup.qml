import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.calendar
import QtQuick
import QtQuick.Layouts

// Clock and month calendar
ColumnLayout {
    spacing: 4

    StyledText {
        text: DateTime.time
        font.pixelSize: 40
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
        color: Appearance.m3colors.m3onSurface
    }
    StyledText {
        text: Qt.locale().toString(DateTime.clock.date, "dddd d MMMM yyyy")
        font.pixelSize: Appearance.font.pixelSize.normal
        color: Appearance.colors.colSubtext
    }
    StyledText {
        text: Translation.tr("Up %1").arg(DateTime.uptime)
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        opacity: 0.8
    }

    CalendarWidget {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 4
    }
}
