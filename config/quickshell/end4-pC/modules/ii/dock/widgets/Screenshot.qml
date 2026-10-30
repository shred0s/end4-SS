import qs.services
import Quickshell

DockWidgetButton {
    symbol: "screenshot_region"
    tooltipText: Translation.tr("Screenshot a region")
    onClicked: Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "screenshot"])
}
