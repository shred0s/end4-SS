import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// Lock, sleep, log out, restart, shut down
ColumnLayout {
    id: root
    property var onChosen: () => {}
    spacing: 2

    PopupHeader {
        Layout.preferredWidth: 260
        Layout.bottomMargin: 6
        icon: "power_settings_new"
        title: SystemInfo.username ?? Translation.tr("Session")
        subtitle: Translation.tr("Up %1").arg(DateTime.uptime)
    }

    Repeater {
        model: [
            { icon: "lock", name: Translation.tr("Lock"), run: () => Session.lock() },
            { icon: "dark_mode", name: Translation.tr("Sleep"), run: () => Session.suspend() },
            { icon: "downloading", name: Translation.tr("Hibernate"), run: () => Session.hibernate() },
            { icon: "logout", name: Translation.tr("Log out"), run: () => Session.logout() },
            { icon: "restart_alt", name: Translation.tr("Restart"), run: () => Session.reboot() },
            { icon: "settings_applications", name: Translation.tr("Restart to firmware"), run: () => Session.rebootToFirmware() },
            { icon: "power_settings_new", name: Translation.tr("Shut down"), run: () => Session.poweroff() }
        ]
        delegate: PopupListButton {
            required property var modelData
            symbol: modelData.icon
            label: modelData.name
            symbolColor: modelData.icon === "power_settings_new" ? Appearance.colors.colError : Appearance.colors.colOnLayer2
            onClicked: {
                root.onChosen();
                modelData.run();
            }
        }
    }
}
