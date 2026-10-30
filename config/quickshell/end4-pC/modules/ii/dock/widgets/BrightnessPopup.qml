import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

// Brightness of every screen, night light and dimming
ColumnLayout {
    id: root
    spacing: 10

    PopupHeader {
        Layout.preferredWidth: 360
        icon: "brightness_6"
        title: Translation.tr("Displays")
        subtitle: Hyprsunset.temperatureActive ? Translation.tr("Night light on") : ""
    }

    Repeater {
        model: Brightness.monitors
        delegate: ColumnLayout {
            id: monitorRow
            required property var modelData
            readonly property bool usable: modelData.ready && isFinite(modelData.brightness)
            visible: monitorRow.usable
            Layout.fillWidth: true
            spacing: 2
            StyledText {
                text: monitorRow.modelData.screen?.name ?? ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            PopupSlider {
                Layout.fillWidth: true
                icon: "brightness_medium"
                value: monitorRow.usable ? monitorRow.modelData.brightness : 0
                onMoved: value => monitorRow.modelData.setBrightness(value)
                onIconClicked: monitorRow.modelData.setBrightness(1)
            }
        }
    }

    // Software dimming (gamma), for screens without brightness control
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        StyledText {
            text: Translation.tr("Dimming")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
        PopupSlider {
            Layout.fillWidth: true
            icon: "contrast"
            from: Hyprsunset.gammaLowerLimit / 100
            value: Hyprsunset.gamma / 100
            onMoved: value => Hyprsunset.setGamma(Math.round(value * 100))
            onIconClicked: Hyprsunset.setGamma(100)
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        PopupToggleTile {
            symbol: "nightlight"
            label: Translation.tr("Night light")
            detail: Hyprsunset.temperatureActive ? Translation.tr("On") : Translation.tr("Off")
            active: Hyprsunset.temperatureActive
            onClicked: Hyprsunset.toggleTemperature()
        }
        PopupToggleTile {
            symbol: Appearance.m3colors.darkmode ? "dark_mode" : "light_mode"
            label: Translation.tr("Dark mode")
            detail: Appearance.m3colors.darkmode ? Translation.tr("On") : Translation.tr("Off")
            active: Appearance.m3colors.darkmode
            onClicked: Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --mode ${Appearance.m3colors.darkmode ? "light" : "dark"} --noswitch`])
        }
    }
}
