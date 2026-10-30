import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell

// Folder stack next to the trash: click fans out the newest downloads
DockWidgetButton {
    id: root
    toneName: "none"
    // DockAppIcon does its own hover and press animation
    scaleContent: false
    holdOpen: fan.isOpen
    toggled: fan.isOpen
    colBackgroundToggled: Appearance.colors.colLayer1Active
    colBackgroundToggledHover: Appearance.colors.colLayer1Active
    tooltipText: Translation.tr("Downloads")
    tooltipEnabled: !fan.isOpen
    onClicked: fan.toggle(root)
    scrollEnabled: fan.isOpen
    onScrolled: step => fan.scroll(-step)

    contentItem: DockAppIcon {
        anchors.centerIn: parent
        iconSource: SystemAppearance.iconPath("folder-downloads", "folder")
        hovered: root.hovered
        pressed: root.down
    }

    DownloadsFan {
        id: fan
    }
}
