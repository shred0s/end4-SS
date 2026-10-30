import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell

// Scroll to change, click for sound settings, middle-click to mute
DockWidgetButton {
    id: root
    popup: SoundPopup {}
    middleClickAction: () => Audio.toggleMute()
    readonly property real volume: Audio.sink?.audio?.volume ?? 0
    readonly property bool muted: Audio.sink?.audio?.muted ?? false

    tooltipText: root.muted ? Translation.tr("Muted") : Translation.tr("Volume %1%").arg(Math.round(root.volume * 100))
    scrollEnabled: true
    onScrolled: step => step < 0 ? Audio.incrementVolume() : Audio.decrementVolume()

    contentItem: Item {
        implicitWidth: ring.implicitSize
        implicitHeight: ring.implicitSize

        CircularProgress {
            cached: false
            id: ring
            anchors.centerIn: parent
            implicitSize: Math.round(DockStyle.iconSize * 0.95)
            lineWidth: 3
            value: root.muted ? 0 : Math.min(1, root.volume)
            colPrimary: root.tonalSurface ? root.toneContent : Appearance.colors.colPrimary
            colSecondary: root.tonalSurface ? ColorUtils.transparentize(root.toneContent, 0.8) : Appearance.colors.colSecondaryContainer
        }

        MaterialSymbol {
            renderType: Text.CurveRendering
            anchors.centerIn: parent
            text: root.muted ? "volume_off" : root.volume < 0.01 ? "volume_mute" : root.volume < 0.5 ? "volume_down" : "volume_up"
            fill: 1
            iconSize: Math.round(DockStyle.iconSize * 0.5)
            color: root.contentColor
        }
    }
}
