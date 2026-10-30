import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell

// Pending package updates. Hidden when there are none.
DockWidgetButton {
    id: root
    popup: UpdatesPopup {
        onUpdate: () => root.closePopup()
    }
    available: Updates.available && Updates.count > 0
    symbol: "deployed_code_update"
    symbolFill: Updates.updateAdvised
    tooltipText: Translation.tr("%1 updates").arg(Updates.count)

    Rectangle {
        z: 2
        x: root.leftInset + root.background.width / 2 + 3
        y: root.topInset + 2
        width: Math.max(height, countText.implicitWidth + 8)
        height: 16
        radius: height / 2
        color: Updates.updateStronglyAdvised ? Appearance.colors.colError : Appearance.colors.colPrimary
        scale: root.scale

        StyledText {
            renderType: Text.CurveRendering
            id: countText
            anchors.centerIn: parent
            text: Updates.count > 99 ? "99+" : Updates.count
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.DemiBold
            color: Updates.updateStronglyAdvised ? Appearance.colors.colOnError : Appearance.colors.colOnPrimary
        }
    }
}
