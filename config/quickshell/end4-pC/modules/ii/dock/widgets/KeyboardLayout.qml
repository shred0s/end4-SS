import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell

// Current layout; click to pick another
DockWidgetButton {
    id: root
    popup: KeyboardLayoutPopup {}
    readonly property bool niri: WM.compositor === "niri"
    readonly property string code: root.niri ? NiriXkb.currentLayoutCode : HyprlandXkb.currentLayoutCode
    readonly property string layoutName: root.niri ? (NiriXkb.currentLayoutName ?? "") : HyprlandXkb.currentLayoutName

    available: root.code !== ""
    tooltipText: root.layoutName !== "" ? root.layoutName : Translation.tr("Keyboard layout")

    contentItem: Item {
        implicitWidth: label.implicitWidth
        implicitHeight: label.implicitHeight

        StyledText {
            renderType: Text.CurveRendering
            id: label
            anchors.centerIn: parent
            text: root.code.toUpperCase()
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.DemiBold
            color: root.contentColor
        }
    }
}
