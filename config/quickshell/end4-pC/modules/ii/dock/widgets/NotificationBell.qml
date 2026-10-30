import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

// Unread count badge; right-click toggles Do not disturb
DockWidgetButton {
    id: root
    popup: NotificationsPopup {}
    symbol: Notifications.silent ? "notifications_off" : Notifications.unread > 0 ? "notifications_unread" : "notifications"
    tooltipText: Notifications.silent ? Translation.tr("Notifications (Do not disturb)")
        : Notifications.unread > 0 ? Translation.tr("%1 unread notifications").arg(Notifications.unread)
        : Translation.tr("Notifications")
    altAction: () => Notifications.silent = !Notifications.silent

    Rectangle {
        visible: Notifications.unread > 0 && !Notifications.silent
        z: 2
        x: root.leftInset + root.background.width / 2 + 4
        y: root.topInset + 2
        width: Math.max(height, badgeText.implicitWidth + 8)
        height: 16
        radius: height / 2
        color: Appearance.colors.colError
        scale: root.scale

        StyledText {
            renderType: Text.CurveRendering
            id: badgeText
            anchors.centerIn: parent
            text: Notifications.unread > 99 ? "99+" : Notifications.unread
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnError
        }
    }
}
