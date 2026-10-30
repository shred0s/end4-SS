import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.notifications
import QtQuick
import QtQuick.Layouts

// The notification list from the sidebar, with Do not disturb
ColumnLayout {
    spacing: 10
    Component.onCompleted: Notifications.markAllRead()

    PopupHeader {
        Layout.preferredWidth: 400
        icon: Notifications.silent ? "notifications_off" : "notifications"
        title: Translation.tr("Notifications")
        subtitle: Notifications.list.length > 0 ? Translation.tr("%1 notifications").arg(Notifications.list.length) : Translation.tr("No notifications")

        StyledText {
            text: Translation.tr("Do not disturb")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
        StyledSwitch {
            checked: Notifications.silent
            onClicked: Notifications.silent = checked
        }
    }

    NotificationList {
        Layout.preferredWidth: 400
        Layout.preferredHeight: 460
    }
}
