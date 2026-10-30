import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

DockButton {
    id: root
    readonly property bool popupOpen: trashPopup.isOpen

    visible: Config.options.dock.showTrashButton
    magnifiable: true
    Layout.topMargin: DockStyle.mTop(DockStyle.pinnedInnerMargin, 0)
    Layout.bottomMargin: DockStyle.mBottom(DockStyle.pinnedInnerMargin, 0)
    Layout.leftMargin: DockStyle.mLeft(DockStyle.pinnedInnerMargin, 0)
    Layout.rightMargin: DockStyle.mRight(DockStyle.pinnedInnerMargin, 0)
    innerInset: DockStyle.iconInset
    outerInset: DockStyle.iconInset
    toggled: root.popupOpen
    colBackgroundToggled: Appearance.colors.colLayer1Active
    colBackgroundToggledHover: Appearance.colors.colLayer1Active
    tooltipText: Trash.count > 0 ? Translation.tr("Trash (%1)").arg(Trash.count) : Translation.tr("Trash")
    tooltipEnabled: !root.popupOpen

    onClicked: trashPopup.toggle(root)

    contentItem: DockAppIcon {
        anchors.centerIn: parent
        iconSource: SystemAppearance.iconPath(Trash.count > 0 ? "user-trash-full" : "user-trash", "user-trash")
        hovered: root.hovered
        pressed: root.down
    }

    TrashPopup {
        id: trashPopup
    }
}
