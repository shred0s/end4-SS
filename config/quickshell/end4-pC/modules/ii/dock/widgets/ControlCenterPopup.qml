import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

// macOS-style Control Center: quick toggles and sliders
ColumnLayout {
    id: root
    // The screen the dock is on, for its brightness
    property var screen: null
    readonly property var monitor: Brightness.getMonitorForScreen(root.screen) ?? null
    spacing: 8

    GridLayout {
        Layout.preferredWidth: 360
        columns: 2
        rowSpacing: 6
        columnSpacing: 6

        PopupToggleTile {
            visible: Network.wifi
            symbol: Network.wifiEnabled ? "wifi" : "wifi_off"
            label: Translation.tr("Wi-Fi")
            detail: Network.wifiEnabled ? (Network.networkName || Translation.tr("On")) : Translation.tr("Off")
            active: Network.wifiEnabled
            onClicked: Network.toggleWifi()
        }
        PopupToggleTile {
            visible: Network.ethernet
            symbol: "lan"
            label: Translation.tr("Ethernet")
            detail: Translation.tr("Connected")
            active: true
        }
        PopupToggleTile {
            visible: BluetoothStatus.available
            symbol: BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
            label: Translation.tr("Bluetooth")
            detail: BluetoothStatus.primaryConnectedDevice?.name ?? (BluetoothStatus.enabled ? Translation.tr("On") : Translation.tr("Off"))
            active: BluetoothStatus.enabled
            onClicked: BluetoothStatus.togglePower()
        }
        PopupToggleTile {
            symbol: Notifications.silent ? "notifications_off" : "notifications_active"
            label: Translation.tr("Do not disturb")
            detail: Notifications.silent ? Translation.tr("On") : Translation.tr("Off")
            active: Notifications.silent
            onClicked: Notifications.silent = !Notifications.silent
        }
        PopupToggleTile {
            symbol: "nightlight"
            label: Translation.tr("Night light")
            detail: Hyprsunset.temperatureActive ? Translation.tr("On") : Translation.tr("Off")
            active: Hyprsunset.temperatureActive
            onClicked: Hyprsunset.toggleTemperature()
        }
        PopupToggleTile {
            symbol: "coffee"
            label: Translation.tr("Keep awake")
            detail: Idle.inhibit ? Translation.tr("On") : Translation.tr("Off")
            active: Idle.inhibit
            onClicked: Idle.toggleInhibit()
        }
        PopupToggleTile {
            symbol: Appearance.m3colors.darkmode ? "dark_mode" : "light_mode"
            label: Translation.tr("Dark mode")
            detail: Appearance.m3colors.darkmode ? Translation.tr("On") : Translation.tr("Off")
            active: Appearance.m3colors.darkmode
            onClicked: Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --mode ${Appearance.m3colors.darkmode ? "light" : "dark"} --noswitch`])
        }
        PopupToggleTile {
            symbol: (Audio.source?.audio?.muted ?? false) ? "mic_off" : "mic"
            label: Translation.tr("Microphone")
            detail: (Audio.source?.audio?.muted ?? false) ? Translation.tr("Muted") : Translation.tr("On")
            active: !(Audio.source?.audio?.muted ?? true)
            onClicked: Audio.toggleMicMute()
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: sliders.implicitHeight + 20
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2

        ColumnLayout {
            id: sliders
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4
            StyledText {
                text: Translation.tr("Sound")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            PopupSlider {
                Layout.fillWidth: true
                icon: (Audio.sink?.audio?.muted ?? false) ? "volume_off" : "volume_up"
                iconToggled: Audio.sink?.audio?.muted ?? false
                value: Audio.sink?.audio?.volume ?? 0
                onMoved: value => { if (Audio.sink?.audio) Audio.sink.audio.volume = value; }
                onIconClicked: Audio.toggleMute()
            }
            StyledText {
                visible: root.monitor?.ready ?? false
                text: Translation.tr("Display")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            PopupSlider {
                visible: (root.monitor?.ready ?? false) && isFinite(root.monitor?.brightness ?? NaN)
                Layout.fillWidth: true
                icon: "brightness_medium"
                value: root.monitor?.brightness ?? 0
                onMoved: value => root.monitor?.setBrightness(value)
                onIconClicked: root.monitor?.setBrightness(1)
            }
        }
    }
}
