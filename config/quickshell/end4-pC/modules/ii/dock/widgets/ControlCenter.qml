import qs
import qs.services
import qs.modules.common
import Quickshell

DockWidgetButton {
    id: root
    popup: ControlCenterPopup {
        screen: root.QsWindow.window?.screen ?? null
    }
    symbol: "toggle_on"
    tooltipText: Translation.tr("Control center")
}
