import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// Previous / play-pause / next for the active player; hidden when nothing can play
DockWidgetButton {
    id: root
    readonly property var player: MprisController.activePlayer
    wide: true
    // Has its own buttons inside; don't zoom the whole row
    scaleContent: false
    available: root.player !== null
    rippleEnabled: false
    colBackgroundHover: root.material ? root.tone : "transparent"
    tooltipText: root.player ? `${root.player.trackTitle ?? ""}${root.player.trackArtist ? " · " + root.player.trackArtist : ""}` : ""

    component ControlButton: MouseArea {
        id: control
        property string symbol
        property bool big: false
        implicitWidth: Math.round(DockStyle.iconSize * (control.big ? 0.95 : 0.75))
        implicitHeight: implicitWidth
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: control.big ? (root.tonalSurface ? root.toneContent : Appearance.colors.colPrimary)
                : control.containsMouse ? ColorUtils.transparentize(root.contentColor, 0.85) : "transparent"
        }

        MaterialSymbol {
            renderType: Text.CurveRendering
            anchors.centerIn: parent
            text: control.symbol
            fill: 1
            iconSize: Math.round(control.width * 0.62)
            color: control.big ? (root.tonalSurface ? root.tone : Appearance.colors.colOnPrimary) : root.contentColor
            scale: control.pressed ? 0.85 : 1
        }
    }

    contentItem: Item {
        implicitWidth: controls.implicitWidth
        implicitHeight: controls.implicitHeight

        GridLayout {
            id: controls
            anchors.centerIn: parent
            columns: DockStyle.vertical ? 1 : -1
            columnSpacing: 2
            rowSpacing: 2

            ControlButton {
                symbol: "skip_previous"
                onClicked: root.player?.previous()
            }
            ControlButton {
                big: true
                symbol: root.player?.isPlaying ? "pause" : "play_arrow"
                onClicked: root.player?.togglePlaying()
            }
            ControlButton {
                symbol: "skip_next"
                onClicked: root.player?.next()
            }
        }
    }
}
