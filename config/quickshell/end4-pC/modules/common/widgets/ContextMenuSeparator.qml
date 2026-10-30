import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

Item {
    Layout.fillWidth: true
    implicitHeight: 9

    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 10
            rightMargin: 10
        }
        implicitHeight: 1
        color: ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.7)
    }
}
