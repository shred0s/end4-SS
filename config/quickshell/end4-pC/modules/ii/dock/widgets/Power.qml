import qs
import qs.services
import qs.modules.common

DockWidgetButton {
    id: root
    popup: PowerPopup {
        onChosen: () => root.closePopup()
    }
    symbol: "power_settings_new"
    tooltipText: Translation.tr("Session")
}
