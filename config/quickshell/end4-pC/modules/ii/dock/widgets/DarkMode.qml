import qs.services
import qs.modules.common
import Quickshell

DockWidgetButton {
    readonly property bool dark: Appearance.m3colors.darkmode
    symbol: dark ? "dark_mode" : "light_mode"
    tooltipText: dark ? Translation.tr("Switch to light mode") : Translation.tr("Switch to dark mode")
    onClicked: Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --mode ${dark ? "light" : "dark"} --noswitch`])
}
