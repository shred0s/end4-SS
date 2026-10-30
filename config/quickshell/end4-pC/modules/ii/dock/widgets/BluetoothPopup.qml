import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.bluetoothDevices
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

// Bluetooth on/off and devices; looks for new devices while open
ColumnLayout {
    id: root
    spacing: 10
    Component.onCompleted: if (Bluetooth.defaultAdapter?.enabled) Bluetooth.defaultAdapter.discovering = true
    Component.onDestruction: if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discovering = false

    PopupHeader {
        Layout.preferredWidth: 360
        icon: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
        title: Translation.tr("Bluetooth")
        subtitle: !BluetoothStatus.enabled ? Translation.tr("Off")
            : BluetoothStatus.activeDeviceCount > 0 ? Translation.tr("%1 connected").arg(BluetoothStatus.activeDeviceCount)
            : Translation.tr("On")

        StyledSwitch {
            checked: BluetoothStatus.enabled
            onClicked: BluetoothStatus.togglePower()
        }
    }

    StyledIndeterminateProgressBar {
        visible: Bluetooth.defaultAdapter?.discovering ?? false
        Layout.fillWidth: true
    }

    StyledListView {
        visible: BluetoothStatus.enabled
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(340, contentHeight)
        clip: true
        spacing: 0
        animateAppearance: false
        model: ScriptModel {
            values: BluetoothStatus.friendlyDeviceList
        }
        delegate: BluetoothDeviceItem {
            required property BluetoothDevice modelData
            device: modelData
            anchors {
                left: parent?.left
                right: parent?.right
            }
        }
    }

    DialogButton {
        Layout.alignment: Qt.AlignRight
        buttonText: Translation.tr("Bluetooth settings")
        onClicked: Quickshell.execDetached(["bash", "-c", Config.options.apps.bluetooth])
    }
}
