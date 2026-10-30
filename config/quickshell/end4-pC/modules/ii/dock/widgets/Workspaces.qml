import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

// This screen's workspace group as dots; the active one is a pill. Scroll to switch.
DockWidgetButton {
    id: root
    wide: true
    // Has its own buttons inside; don't zoom the whole row
    scaleContent: false
    colBackgroundHover: root.material ? root.tone : "transparent"
    rippleEnabled: false
    tooltipText: Translation.tr("Workspace %1").arg(workspaces.activeNumber)
    scrollEnabled: true
    onScrolled: step => WM.switchWorkspaceRelative(step > 0 ? "next" : "prev")

    readonly property real dot: Math.max(8, Math.round(DockStyle.iconSize * 0.3))

    WorkspaceModel {
        id: workspaces
        screen: root.QsWindow.window?.screen ?? null
    }

    contentItem: Item {
        implicitWidth: grid.implicitWidth
        implicitHeight: grid.implicitHeight

        GridLayout {
            id: grid
            anchors.centerIn: parent
            columns: DockStyle.vertical ? 1 : -1
            columnSpacing: 5
            rowSpacing: 5

            Repeater {
                model: workspaces.shownCount
                delegate: Rectangle {
                    id: dot
                    required property int index
                    readonly property int number: workspaces.group * workspaces.shownCount + index + 1
                    readonly property bool active: number === workspaces.activeNumber
                    readonly property bool occupied: workspaces.occupied[index] ?? false
                    readonly property color accent: root.tonalSurface ? root.toneContent : Appearance.colors.colPrimary

                    implicitWidth: DockStyle.vertical ? root.dot : (active ? root.dot * 2.6 : root.dot)
                    implicitHeight: DockStyle.vertical ? (active ? root.dot * 2.6 : root.dot) : root.dot
                    radius: root.dot / 2
                    color: active ? dot.accent
                        : occupied ? ColorUtils.transparentize(root.contentColor, 0.35)
                        : ColorUtils.transparentize(root.contentColor, 0.8)
                    scale: dotArea.containsMouse && !active ? 1.25 : 1

                    Behavior on implicitWidth {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on implicitHeight {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                    Behavior on scale {
                        NumberAnimation { duration: Appearance.animation.elementMoveSmall.duration }
                    }

                    MouseArea {
                        id: dotArea
                        anchors.fill: parent
                        anchors.margins: -3
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: WM.switchWorkspace(workspaces.getWorkspaceIdAt(dot.index))
                    }
                }
            }
        }
    }
}
