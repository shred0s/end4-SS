import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Current weather in detail
ColumnLayout {
    id: root
    spacing: 12
    readonly property var weather: Weather.data

    RowLayout {
        spacing: 12
        MaterialSymbol {
            text: Icons.getWeatherIcon(root.weather.wCode) ?? "cloud"
            iconSize: 52
            fill: 1
            color: Appearance.colors.colPrimary
        }
        ColumnLayout {
            spacing: 0
            StyledText {
                text: root.weather.temp || "--°"
                font.pixelSize: 34
                font.weight: Font.DemiBold
                color: Appearance.m3colors.m3onSurface
            }
            StyledText {
                text: Translation.tr("Feels like %1").arg(root.weather.tempFeelsLike || "--")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }
        Item { Layout.fillWidth: true }
        ColumnLayout {
            spacing: 0
            StyledText {
                Layout.alignment: Qt.AlignRight
                text: root.weather.city || Translation.tr("Weather")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.m3colors.m3onSurface
            }
            StyledText {
                Layout.alignment: Qt.AlignRight
                visible: (root.weather.lastRefresh ?? "") !== ""
                text: Translation.tr("Updated %1").arg(root.weather.lastRefresh)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }

    GridLayout {
        Layout.preferredWidth: 340
        columns: 3
        rowSpacing: 6
        columnSpacing: 6

        Repeater {
            model: [
                { icon: "water_drop", name: Translation.tr("Humidity"), value: `${String(root.weather.humidity ?? "--").replace(/%$/, "")}%` },
                { icon: "air", name: Translation.tr("Wind"), value: root.weather.wind || "--" },
                { icon: "sunny", name: Translation.tr("UV index"), value: `${root.weather.uv ?? "--"}` },
                { icon: "rainy", name: Translation.tr("Rain"), value: root.weather.precip || "--" },
                { icon: "visibility", name: Translation.tr("Visibility"), value: root.weather.visib || "--" },
                { icon: "compress", name: Translation.tr("Pressure"), value: root.weather.press || "--" },
                { icon: "wb_twilight", name: Translation.tr("Sunrise"), value: `${root.weather.sunrise ?? "--"}` },
                { icon: "routine", name: Translation.tr("Sunset"), value: `${root.weather.sunset ?? "--"}` }
            ]
            delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 58
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 0
                    RowLayout {
                        spacing: 4
                        MaterialSymbol {
                            text: modelData.icon
                            iconSize: 15
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            text: modelData.name
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: modelData.value
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                    }
                }
            }
        }
    }

    DialogButton {
        Layout.alignment: Qt.AlignRight
        buttonText: Translation.tr("Refresh")
        onClicked: Weather.getData()
    }
}
