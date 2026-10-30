import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell

// The dock's launcher button, shown as the distro logo like a Start button.
// Opens whatever Super opens: the start menu, or the overview (search and workspaces).
DockWidgetButton {
    id: root
    readonly property string screenName: root.QsWindow.window?.screen?.name ?? ""
    readonly property bool open: Launcher.startMenu
        ? GlobalStates.startMenuOpen && GlobalStates.startMenuScreen === root.screenName
        : GlobalStates.overviewOpen

    tooltipText: Launcher.startMenu ? Translation.tr("Start") : Translation.tr("Search")
    tooltipEnabled: !root.open
    active: root.open
    onClicked: Launcher.toggleFromClick(root.screenName)

    contentItem: Item {
        implicitWidth: logo.width
        implicitHeight: logo.height

        CustomIcon {
            id: logo
            anchors.centerIn: parent
            width: Math.round(DockStyle.iconSize * 0.62)
            height: width
            source: Config.options.custom.distroIcon || SystemInfo.distroIcon
            customFolder: Config.options.custom.iconsPath
            colorize: Config.options.custom.colorizeIcon
            color: root.contentColor
        }
    }
}
