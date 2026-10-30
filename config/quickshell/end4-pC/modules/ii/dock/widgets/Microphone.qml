import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell

// Scroll for input volume, click for input settings, middle-click to mute
DockWidgetButton {
    id: root
    popup: SoundPopup {
        isSink: false
    }
    middleClickAction: () => Audio.toggleMicMute()
    readonly property bool muted: Audio.source?.audio?.muted ?? false
    readonly property real volume: Audio.source?.audio?.volume ?? 0

    tooltipText: root.muted ? Translation.tr("Microphone muted") : Translation.tr("Microphone %1%").arg(Math.round(root.volume * 100))
    scrollEnabled: true
    onScrolled: step => {
        if (!Audio.source?.audio) return;
        Audio.source.audio.volume = Math.max(0, Math.min(1, root.volume - step * 0.05));
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
            value: root.muted ? 0 : Math.min(1, root.volume)
            colPrimary: root.tonalSurface ? root.toneContent : Appearance.colors.colPrimary
            colSecondary: root.tonalSurface ? ColorUtils.transparentize(root.toneContent, 0.8) : Appearance.colors.colSecondaryContainer
        }

        MaterialSymbol {
            renderType: Text.CurveRendering
            anchors.centerIn: parent
            text: root.muted ? "mic_off" : "mic"
            fill: 1
            iconSize: Math.round(DockStyle.iconSize * 0.5)
            color: root.contentColor
        }
    }
}
