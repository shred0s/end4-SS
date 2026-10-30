import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// CPU, memory, swap and disk, with recent history
ColumnLayout {
    id: root
    spacing: 10
    Component.onCompleted: ResourceUsage.consumers++
    Component.onDestruction: ResourceUsage.consumers--

    component Meter: ColumnLayout {
        id: meter
        property string icon
        property string name
        property string detail
        property real value
        property var history: []
        readonly property color color: meter.value > 0.9 ? Appearance.colors.colError : Appearance.colors.colPrimary
        Layout.fillWidth: true
        spacing: 4

        RowLayout {
            spacing: 6
            MaterialSymbol {
                text: meter.icon
                iconSize: 18
                color: meter.color
            }
            StyledText {
                text: meter.name
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.m3colors.m3onSurface
            }
            Item { Layout.fillWidth: true }
            StyledText {
                text: meter.detail
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.features: { "tnum": 1 }
                color: Appearance.colors.colSubtext
            }
            StyledText {
                Layout.preferredWidth: 40
                horizontalAlignment: Text.AlignRight
                text: `${Math.round(meter.value * 100)}%`
                font.pixelSize: Appearance.font.pixelSize.small
                font.features: { "tnum": 1 }
                color: Appearance.m3colors.m3onSurface
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: meter.history.length > 1 ? 42 : 8
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2
            clip: true

            Graph {
                anchors.fill: parent
                visible: meter.history.length > 1
                values: meter.history
                points: Math.max(2, meter.history.length)
                color: meter.color
                fillOpacity: 0.3
            }
            Rectangle {
                visible: meter.history.length <= 1
                width: parent.width * Math.min(1, meter.value)
                height: parent.height
                radius: parent.radius
                color: meter.color
            }
        }
    }

    PopupHeader {
        Layout.preferredWidth: 360
        icon: "memory"
        title: Translation.tr("Resources")
        subtitle: ResourceUsage.cpuTemp > 0 ? Translation.tr("CPU at %1 °C").arg(Math.round(ResourceUsage.cpuTemp)) : ""
    }

    Meter {
        icon: "planner_review"
        name: Translation.tr("CPU")
        value: ResourceUsage.cpuUsage
        history: ResourceUsage.cpuUsageHistory
    }
    Meter {
        icon: "memory"
        name: Translation.tr("Memory")
        detail: `${ResourceUsage.kbToGbString(ResourceUsage.memoryUsed)} / ${ResourceUsage.maxAvailableMemoryString}`
        value: ResourceUsage.memoryUsedPercentage
        history: ResourceUsage.memoryUsageHistory
    }
    Meter {
        visible: ResourceUsage.swapTotal > 1
        icon: "swap_horiz"
        name: Translation.tr("Swap")
        detail: `${ResourceUsage.kbToGbString(ResourceUsage.swapUsed)} / ${ResourceUsage.maxAvailableSwapString}`
        value: ResourceUsage.swapUsedPercentage
    }
    Meter {
        icon: "hard_drive"
        name: Translation.tr("Disk")
        detail: `${ResourceUsage.kbToGbString(ResourceUsage.diskUsed)} / ${ResourceUsage.maxAvailableDiskString}`
        value: ResourceUsage.diskUsedPercentage
    }

    DialogButton {
        Layout.alignment: Qt.AlignRight
        buttonText: Translation.tr("Task manager")
        onClicked: Session.launchTaskManager()
    }
}
