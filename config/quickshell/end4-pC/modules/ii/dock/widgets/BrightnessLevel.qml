import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell

// This screen's brightness: scroll to change (below 0% it dims with gamma), click for all displays
DockWidgetButton {
    id: root
    readonly property var monitor: Brightness.getMonitorForScreen(root.QsWindow.window?.screen ?? null) ?? null
    readonly property bool hardware: (root.monitor?.ready ?? false) && isFinite(root.monitor?.brightness ?? NaN)
    readonly property real level: root.hardware ? root.monitor.brightness : Hyprsunset.gamma / 100

    tooltipText: Translation.tr("Brightness %1%").arg(Math.round(root.level * 100))
    scrollEnabled: true
    onScrolled: step => step < 0 ? root.brighter() : root.dimmer()
    popup: BrightnessPopup {}

    function brighter() {
        if (Hyprsunset.gamma < 100 || !root.hardware) Hyprsunset.setGamma(Math.min(100, Hyprsunset.gamma + 5));
        else root.monitor.setBrightness(root.monitor.brightness + 0.05);
    }

    function dimmer() {
        if (root.hardware && root.monitor.brightness > 0) root.monitor.setBrightness(root.monitor.brightness - 0.05);
        else Hyprsunset.setGamma(Math.max(Hyprsunset.gammaLowerLimit, Hyprsunset.gamma - 5));
    }

    contentItem: Item {
        implicitWidth: ring.implicitSize
        implicitHeight: ring.implicitSize

        CircularProgress {
            cached: false
            id: ring
            anchors.centerIn: parent
            implicitSize: Math.round(DockStyle.iconSize * 0.95)
            lineWidth: 3
            value: Math.min(1, root.level)
            colPrimary: root.tonalSurface ? root.toneContent : Appearance.colors.colPrimary
            colSecondary: root.tonalSurface ? ColorUtils.transparentize(root.toneContent, 0.8) : Appearance.colors.colSecondaryContainer
        }

        MaterialSymbol {
            renderType: Text.CurveRendering
            anchors.centerIn: parent
            text: root.level < 0.34 ? "brightness_low" : root.level < 0.67 ? "brightness_medium" : "brightness_high"
            fill: 1
            iconSize: Math.round(DockStyle.iconSize * 0.5)
            color: root.contentColor
        }
    }
}
