import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

// Download and upload rates across all interfaces
DockWidgetButton {
    id: root
    popup: NetworkPopup {
        downRate: root.downRate
        upRate: root.upRate
        formatRate: rate => root.format(rate, false)
    }
    wide: true
    property real downRate: 0
    property real upRate: 0
    property real lastReceived: -1
    property real lastSent: -1
    property double lastTime: 0

    tooltipText: Translation.tr("Download %1 · Upload %2").arg(root.format(root.downRate, false)).arg(root.format(root.upRate, false))

    function format(rate, compact) {
        const units = compact ? ["B", "K", "M", "G"] : ["B/s", "KB/s", "MB/s", "GB/s"];
        let value = Math.max(0, Number(rate) || 0);
        let unit = 0;
        while (value >= 1024 && unit < units.length - 1) {
            value /= 1024;
            unit++;
        }
        return `${value.toFixed(unit > 0 && value < 100 ? 1 : 0)}${compact ? "" : " "}${units[unit]}`;
    }

    function sample(contents) {
        let received = 0;
        let sent = 0;
        for (const line of contents.split("\n")) {
            const colon = line.indexOf(":");
            if (colon < 0) continue;
            const name = line.slice(0, colon).trim();
            if (name === "" || name === "lo") continue;
            const fields = line.slice(colon + 1).trim().split(/\s+/);
            if (fields.length < 9) continue;
            received += Number(fields[0]) || 0;
            sent += Number(fields[8]) || 0;
        }
        const now = Date.now();
        if (root.lastTime > 0 && now > root.lastTime) {
            root.downRate = Math.max(0, received - root.lastReceived) * 1000 / (now - root.lastTime);
            root.upRate = Math.max(0, sent - root.lastSent) * 1000 / (now - root.lastTime);
        }
        root.lastReceived = received;
        root.lastSent = sent;
        root.lastTime = now;
    }

    FileView {
        id: stats
        path: "/proc/net/dev"
        printErrors: false
        onLoaded: root.sample(stats.text())
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.visible
        onTriggered: stats.reload()
    }

    contentItem: Item {
        implicitWidth: column.implicitWidth
        implicitHeight: column.implicitHeight

        GridLayout {
            id: column
            anchors.centerIn: parent
            columns: 2
            rowSpacing: -2
            columnSpacing: 2

            MaterialSymbol { renderType: Text.CurveRendering; text: "arrow_downward"; iconSize: Appearance.font.pixelSize.small; color: root.contentColor }
            StyledText {
                renderType: Text.CurveRendering
                Layout.preferredWidth: 46
                text: root.format(root.downRate, true)
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.features: { "tnum": 1 }
                color: root.contentColor
            }
            MaterialSymbol { renderType: Text.CurveRendering; text: "arrow_upward"; iconSize: Appearance.font.pixelSize.small; color: root.contentColor }
            StyledText {
                renderType: Text.CurveRendering
                Layout.preferredWidth: 46
                text: root.format(root.upRate, true)
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.features: { "tnum": 1 }
                color: root.contentColor
            }
        }
    }
}
