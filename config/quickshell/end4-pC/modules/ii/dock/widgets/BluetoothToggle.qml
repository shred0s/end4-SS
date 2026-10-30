import qs.services
import qs.modules.common
import Quickshell

// Click for devices, middle-click turns Bluetooth on or off
DockWidgetButton {
    popup: BluetoothPopup {}
    middleClickAction: () => BluetoothStatus.togglePower()
    available: BluetoothStatus.available
    symbol: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
    tooltipText: !BluetoothStatus.enabled ? Translation.tr("Bluetooth off")
        : BluetoothStatus.primaryConnectedDevice ? (BluetoothStatus.primaryConnectedDevice.name ?? Translation.tr("Connected"))
        : Translation.tr("Bluetooth on")
}
