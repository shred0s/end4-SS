import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

DockWidgetButton {
    id: root
    popup: WeatherPopup {}
    wide: true
    tooltipText: Weather.data.city !== "" ? `${Weather.data.city}: ${Weather.data.temp}, ${Translation.tr("feels like")} ${Weather.data.tempFeelsLike}` : Translation.tr("Weather")

    contentItem: Item {
        implicitWidth: grid.implicitWidth
        implicitHeight: grid.implicitHeight

        GridLayout {
            id: grid
            anchors.centerIn: parent
            columns: DockStyle.vertical ? 1 : 2
            columnSpacing: 4
            rowSpacing: 0

            MaterialSymbol {
                renderType: Text.CurveRendering
                Layout.alignment: Qt.AlignCenter
                text: Icons.getWeatherIcon(Weather.data.wCode) ?? "cloud"
                fill: 1
                iconSize: Math.round(DockStyle.iconSize * 0.62)
                color: root.contentColor
            }

            StyledText {
                renderType: Text.CurveRendering
                Layout.alignment: Qt.AlignCenter
                text: (Weather.data?.temp ?? "--°").replace(/[CF]$/, "")
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
                color: root.contentColor
            }
        }
    }
}
