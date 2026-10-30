import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/*
 * Round previous/next button shown over the video while it's hovered.
 */
RippleButton {
    id: root
    property string symbol
    property string tooltip
    property bool shown: false
    focusPolicy: Qt.NoFocus
    implicitWidth: 48
    implicitHeight: 48
    buttonRadius: height / 2
    opacity: shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    colBackground: ColorUtils.transparentize("#000000", 0.5)
    colBackgroundHover: ColorUtils.transparentize("#000000", 0.3)
    colRipple: ColorUtils.transparentize("#000000", 0.15)
    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.symbol
        iconSize: 32
        color: "#ffffff"
    }
    StyledToolTip {
        text: root.tooltip
    }
}
