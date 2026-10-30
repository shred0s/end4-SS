import qs.services
import qs.modules.common

DockWidgetButton {
    symbol: "coffee"
    symbolFill: Idle.inhibit
    active: Idle.inhibit
    tooltipText: Idle.inhibit ? Translation.tr("Keeping awake") : Translation.tr("Keep awake")
    onClicked: Idle.toggleInhibit()
}
