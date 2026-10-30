import qs.modules.common
import qs.modules.ii.sidebarLeft
import QtQuick

// The left sidebar's pages (assistant, translator, ...) in a popup
Item {
    implicitWidth: Appearance.sizes.sidebarWidth
    implicitHeight: 640

    SidebarLeftContent {
        anchors.fill: parent
        scopeRoot: null
    }
}
