import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.wifiNetworks
import QtQuick
import QtQuick.Layouts
import Quickshell

// Connection details, current speed and Wi-Fi networks
ColumnLayout {
    id: root
    // Rates from the network speed widget; below 0 hides them
    property real downRate: -1
    property real upRate: -1
    property var formatRate: rate => `${Math.round(rate)} B/s`
    spacing: 10
    Component.onCompleted: if (Network.wifiEnabled) Network.rescanWifi()

    PopupHeader {
        Layout.preferredWidth: 360
        icon: Network.materialSymbol
        title: Network.ethernet ? Translation.tr("Ethernet") : Network.networkName !== "" ? Network.networkName : Translation.tr("Not connected")
        subtitle: Network.ipAddress !== "" ? Network.ipAddress : ""

        StyledSwitch {
            visible: Network.wifi
            checked: Network.wifiEnabled
            onClicked: Network.enableWifi(checked)
        }
    }

    RowLayout {
        visible: root.downRate >= 0
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: [
                { icon: "arrow_downward", name: Translation.tr("Download"), rate: root.downRate },
                { icon: "arrow_upward", name: Translation.tr("Upload"), rate: root.upRate }
            ]
            delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 52
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    MaterialSymbol {
                        text: modelData.icon
                        iconSize: 20
                        color: Appearance.colors.colPrimary
                    }
                    ColumnLayout {
                        spacing: -2
                        StyledText {
                            text: modelData.name
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            text: root.formatRate(modelData.rate)
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                            color: Appearance.colors.colOnLayer2
                        }
                    }
                }
            }
        }
    }

    StyledIndeterminateProgressBar {
        visible: Network.wifiScanning
        Layout.fillWidth: true
    }

    ListView {
        visible: Network.wifi && Network.wifiEnabled
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(320, contentHeight)
        clip: true
        spacing: 0
        model: ScriptModel {
            values: Network.friendlyWifiNetworks
        }
        delegate: WifiNetworkItem {
            required property WifiAccessPoint modelData
            wifiNetwork: modelData
            width: ListView.view.width
        }
    }

    DialogButton {
        Layout.alignment: Qt.AlignRight
        buttonText: Translation.tr("Network settings")
        onClicked: Quickshell.execDetached(["bash", "-c", Network.ethernet ? Config.options.apps.networkEthernet : Config.options.apps.network])
    }
}
