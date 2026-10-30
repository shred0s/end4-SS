import qs
import qs.services
import qs.modules.common

DockWidgetButton {
    id: root
    popup: SearchPopup {
        onLaunched: () => root.closePopup()
    }
    symbol: "search"
    tooltipText: Translation.tr("Search")
}
