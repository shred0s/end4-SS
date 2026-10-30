import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick

DockWidgetButton {
    id: root
    popup: BatteryPopup {}
    readonly property real level: Battery.percentage
    readonly property color levelColor: Battery.isLowAndNotCharging ? Appearance.colors.colError
        : root.tonalSurface ? root.toneContent : Appearance.colors.colPrimary

    available: Battery.available
    tooltipText: Battery.isCharging ? Translation.tr("Charging, %1%").arg(Math.round(root.level * 100))
        : Translation.tr("Battery %1%").arg(Math.round(root.level * 100))

    contentItem: Item {
        implicitWidth: ring.implicitSize
        implicitHeight: ring.implicitSize

        CircularProgress {
            cached: false
            id: ring
            anchors.centerIn: parent
            implicitSize: Math.round(DockStyle.iconSize * 0.95)
            lineWidth: 3
            value: root.level
            colPrimary: root.levelColor
            colSecondary: ColorUtils.transparentize(root.levelColor, 0.8)
        }

        MaterialSymbol {
            renderType: Text.CurveRendering
            anchors.centerIn: parent
            text: Battery.isCharging ? "bolt" : "battery_full"
            fill: 1
            iconSize: Math.round(DockStyle.iconSize * 0.45)
            color: root.levelColor
        }
    }
}
