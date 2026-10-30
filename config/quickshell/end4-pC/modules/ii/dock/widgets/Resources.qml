import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

// CPU and memory rings; click opens the task manager
DockWidgetButton {
    id: root
    popup: ResourcesPopup {}
    wide: true
    tooltipText: Translation.tr("CPU %1% · Memory %2%")
        .arg(Math.round(ResourceUsage.cpuUsage * 100))
        .arg(Math.round(ResourceUsage.memoryUsedPercentage * 100))

    Component.onCompleted: ResourceUsage.consumers++
    Component.onDestruction: ResourceUsage.consumers--

    component Ring: Item {
        id: ring
        property real value
        property string symbol
        readonly property color color: ring.value > 0.9 ? Appearance.colors.colError
            : root.tonalSurface ? root.toneContent : Appearance.colors.colPrimary
        implicitWidth: progress.implicitSize
        implicitHeight: progress.implicitSize

        CircularProgress {
            cached: false
            id: progress
            anchors.centerIn: parent
            implicitSize: Math.round(DockStyle.iconSize * 0.85)
            lineWidth: 3
            value: ring.value
            colPrimary: ring.color
            colSecondary: ColorUtils.transparentize(ring.color, 0.8)
        }

        MaterialSymbol {
            renderType: Text.CurveRendering
            anchors.centerIn: parent
            text: ring.symbol
            fill: 1
            iconSize: Math.round(DockStyle.iconSize * 0.4)
            color: root.contentColor
        }
    }

    contentItem: Item {
        implicitWidth: grid.implicitWidth
        implicitHeight: grid.implicitHeight

        GridLayout {
            id: grid
            anchors.centerIn: parent
            columns: DockStyle.vertical ? 1 : 2
            columnSpacing: 5
            rowSpacing: 5

            Ring {
                value: ResourceUsage.cpuUsage
                symbol: "planner_review"
            }
            Ring {
                value: ResourceUsage.memoryUsedPercentage
                symbol: "memory"
            }
        }
    }
}
