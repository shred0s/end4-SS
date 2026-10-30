import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    readonly property string style: DockStyle.separatorStyle
    // Islands are split at separators, unless this one is a divider inside an island
    readonly property bool isDockSeparator: true
    property bool splitsIsland: true
    readonly property bool gapOnly: DockStyle.islands && root.splitsIsland

    Layout.topMargin: DockStyle.mTop(DockStyle.separatorInnerMargin, DockStyle.separatorOuterMargin)
    Layout.bottomMargin: DockStyle.mBottom(DockStyle.separatorInnerMargin, DockStyle.separatorOuterMargin)
    Layout.leftMargin: DockStyle.mLeft(DockStyle.separatorInnerMargin, DockStyle.separatorOuterMargin)
    Layout.rightMargin: DockStyle.mRight(DockStyle.separatorInnerMargin, DockStyle.separatorOuterMargin)
    Layout.fillHeight: !DockStyle.vertical
    Layout.fillWidth: DockStyle.vertical
    readonly property real thickness: root.gapOnly ? DockStyle.islandGap + 2 * (DockStyle.backgroundPadding - DockStyle.spacing)
        : root.style === "dot" ? 4 : root.style === "gap" ? 6 : 1
    transform: Translate { x: DockStyle.magnifying ? DockMagnify.shiftOf(root) : 0 }
    implicitWidth: DockStyle.vertical ? 1 : thickness
    implicitHeight: DockStyle.vertical ? thickness : 1

    Rectangle {
        visible: root.style === "line" && !root.gapOnly
        anchors.fill: parent
        color: Appearance.colors.colOutlineVariant
    }

    // Fades out towards both ends
    Rectangle {
        visible: root.style === "fade" && !root.gapOnly
        anchors.fill: parent
        gradient: Gradient {
            orientation: DockStyle.vertical ? Gradient.Horizontal : Gradient.Vertical
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.5; color: Appearance.colors.colOutline }
            GradientStop { position: 1; color: "transparent" }
        }
    }

    Rectangle {
        visible: root.style === "dot" && !root.gapOnly
        anchors.centerIn: parent
        width: 4
        height: 4
        radius: 2
        color: Appearance.colors.colOutline
    }
}
