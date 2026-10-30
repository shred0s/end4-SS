import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

// Keyboard layouts; click one to switch to it
ColumnLayout {
    id: root
    readonly property bool niri: WM.compositor === "niri"
    readonly property var codes: root.niri ? (NiriXkb.layoutCodes ?? []) : HyprlandXkb.layoutCodes
    readonly property string current: root.niri ? NiriXkb.currentLayoutCode : HyprlandXkb.currentLayoutCode
    spacing: 2

    PopupHeader {
        Layout.preferredWidth: 240
        Layout.bottomMargin: 6
        icon: "keyboard"
        title: Translation.tr("Keyboard layout")
        subtitle: (root.niri ? NiriXkb.currentLayoutName : HyprlandXkb.currentLayoutName) ?? ""
    }

    Repeater {
        model: root.codes
        delegate: PopupListButton {
            required property string modelData
            required property int index
            label: modelData.toUpperCase()
            selected: modelData === root.current
            onClicked: Quickshell.execDetached(root.niri
                ? ["niri", "msg", "action", "switch-layout", `${index}`]
                : ["hyprctl", "switchxkblayout", "all", `${index}`])
        }
    }
}
