import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

// Pending updates; updating runs in a terminal
ColumnLayout {
    id: root
    property var onUpdate: () => {}
    spacing: 10

    PopupHeader {
        Layout.preferredWidth: 320
        icon: "deployed_code_update"
        title: Updates.count > 0 ? Translation.tr("%1 updates available").arg(Updates.count) : Translation.tr("Up to date")
        subtitle: Updates.checking ? Translation.tr("Checking…")
            : Updates.updateStronglyAdvised ? Translation.tr("It's been a while, update soon")
            : ""
    }

    RowLayout {
        Layout.alignment: Qt.AlignRight
        spacing: 4
        DialogButton {
            buttonText: Translation.tr("Check again")
            enabled: !Updates.checking
            onClicked: Updates.refresh()
        }
        DialogButton {
            buttonText: Translation.tr("Update now")
            enabled: Updates.count > 0
            onClicked: {
                Quickshell.execDetached(["bash", "-c", Config.options.apps.update]);
                root.onUpdate();
            }
        }
    }
}
