import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// Full-width row in a popup list: icon, text, optional detail and a check when selected
RippleButton {
    id: root
    property string symbol
    property string label
    property string detail
    property bool selected: false
    property color symbolColor: Appearance.colors.colOnLayer2

    Layout.fillWidth: true
    implicitHeight: 40
    horizontalPadding: 10
    buttonRadius: Appearance.rounding.small
    colBackground: root.selected ? Appearance.colors.colSecondaryContainer : ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
    colBackgroundHover: root.selected ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover

    contentItem: RowLayout {
        spacing: 10
        MaterialSymbol {
            visible: root.symbol !== ""
            text: root.symbol
            iconSize: 20
            color: root.selected ? Appearance.colors.colOnSecondaryContainer : root.symbolColor
        }
        StyledText {
            Layout.fillWidth: true
            text: root.label
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.m3colors.m3onSurface
        }
        StyledText {
            visible: root.detail !== ""
            text: root.detail
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
        MaterialSymbol {
            visible: root.selected
            text: "check"
            iconSize: 18
            color: Appearance.colors.colOnSecondaryContainer
        }
    }
}
