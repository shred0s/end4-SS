import qs
import qs.services
import qs.modules.common
import Quickshell

DockWidgetButton {
    popup: NetworkPopup {}
    symbol: Network.materialSymbol
    tooltipText: Network.ethernet ? Translation.tr("Ethernet")
        : Network.networkName !== "" ? `${Network.networkName} (${Network.networkStrength}%)`
        : Translation.tr("Not connected")
}
