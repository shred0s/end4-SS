import qs.services
import Quickshell

DockWidgetButton {
    symbol: "colorize"
    tooltipText: Translation.tr("Pick a color")
    onClicked: Quickshell.execDetached(["hyprpicker", "-a"])
}
