import qs
import qs.services
import qs.modules.common

DockWidgetButton {
    symbol: "keyboard_alt"
    tooltipText: Translation.tr("On-screen keyboard")
    active: GlobalStates.oskOpen
    onClicked: GlobalStates.oskOpen = !GlobalStates.oskOpen
}
