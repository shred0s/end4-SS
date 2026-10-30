import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * Widget island in a screen corner, at one end of the dock's edge (left or
 * right on a bottom dock, top or bottom on a side dock). Slides in and out
 * with the dock. On a hugging dock it's a tab flush in the corner; on a panel
 * it sits inside the strip without its own background.
 */
MouseArea {
    id: root

    property var widgets: []
    // Right corner on a bottom dock, bottom corner on a side dock
    property bool atEnd: false
    // How far the dock is slid off screen
    property real offset: 0
    property real revealProgress: 1
    property color fill
    property color tint
    property real borderWidth: 0
    property bool animate: true
    readonly property bool shown: row.length > 0
    readonly property bool holdOpen: row.holdOpen

    readonly property string position: DockStyle.position
    readonly property bool vertical: DockStyle.vertical
    readonly property real gap: Appearance.sizes.hyprlandGapsOut
    readonly property real shadowMargin: Appearance.sizes.elevationMargin
    // Distance from the screen side
    readonly property real sideInset: DockStyle.panel ? 6 : DockStyle.hug ? 0 : root.gap
    readonly property real length: row.length + DockStyle.backgroundPadding * 2
    readonly property real cornerRadius: DockStyle.material ? Appearance.rounding.full : Config.options.dock.radius

    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    visible: root.shown
    width: root.vertical ? DockStyle.thickness : (root.shown ? root.length : 0)
    height: root.vertical ? (root.shown ? root.length : 0) : DockStyle.thickness

    anchors {
        bottom: root.position === "bottom" || (root.vertical && root.atEnd) ? parent.bottom : undefined
        bottomMargin: root.position === "bottom" ? -root.offset : root.sideInset
        top: root.vertical && !root.atEnd ? parent.top : undefined
        topMargin: root.sideInset
        left: root.position === "left" || (root.position === "bottom" && !root.atEnd) ? parent.left : undefined
        leftMargin: root.position === "left" ? -root.offset : root.sideInset
        right: root.position === "right" || (root.position === "bottom" && root.atEnd) ? parent.right : undefined
        rightMargin: root.position === "right" ? -root.offset : root.sideInset
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: DockStyle.revealAnimation === "fade" || DockStyle.revealAnimation === "zoom" ? root.revealProgress : 1
        scale: DockStyle.revealAnimation === "zoom" ? 0.8 + 0.2 * root.revealProgress : 1
        transformOrigin: root.position === "left" ? Item.Left : root.position === "right" ? Item.Right : Item.Bottom

        DockSurface {
            id: surface
            visible: !DockStyle.panel && Config.options.dock.showBackground
            // Distance from the screen edge and from the inner side, across the dock
            readonly property real edgeMargin: DockStyle.material ? DockStyle.materialEdgeMargin : root.gap
            readonly property real innerMargin: DockStyle.material ? DockStyle.materialInnerMargin : root.shadowMargin
            anchors {
                fill: parent
                topMargin: root.position === "bottom" ? surface.innerMargin : 0
                bottomMargin: root.position === "bottom" ? surface.edgeMargin : 0
                leftMargin: root.position === "left" ? surface.edgeMargin : root.position === "right" ? surface.innerMargin : 0
                rightMargin: root.position === "right" ? surface.edgeMargin : root.position === "left" ? surface.innerMargin : 0
            }
            flat: DockStyle.material
            fill: DockStyle.material ? DockStyle.materialPillColor : root.fill
            tint: root.tint
            borderWidth: DockStyle.hug ? 0 : root.borderWidth
            animate: root.animate
            // A hugging tab only rounds the corner that points into the screen
            radius: root.cornerRadius
            topLeftRadius: !DockStyle.hug ? radius : (root.position === "bottom" && root.atEnd) || (root.position === "right" && root.atEnd) ? radius : 0
            topRightRadius: !DockStyle.hug ? radius : (root.position === "bottom" && !root.atEnd) || (root.position === "left" && root.atEnd) ? radius : 0
            bottomLeftRadius: !DockStyle.hug ? radius : root.position === "right" && !root.atEnd ? radius : 0
            bottomRightRadius: !DockStyle.hug ? radius : root.position === "left" && !root.atEnd ? radius : 0
        }

        // Hugging tab: curves into the screen edge on its inner side
        RoundCorner {
            visible: DockStyle.hug && surface.visible
            implicitSize: Appearance.rounding.screenRounding
            color: root.fill
            anchors {
                left: root.position === "bottom" ? (root.atEnd ? undefined : surface.right)
                    : root.position === "left" ? surface.left : undefined
                right: root.position === "bottom" ? (root.atEnd ? surface.left : undefined)
                    : root.position === "right" ? surface.right : undefined
                bottom: root.position === "bottom" ? surface.bottom : root.atEnd ? surface.top : undefined
                top: root.vertical && !root.atEnd ? surface.bottom : undefined
            }
            corner: root.position === "bottom" ? (root.atEnd ? RoundCorner.CornerEnum.BottomRight : RoundCorner.CornerEnum.BottomLeft)
                : root.position === "left" ? (root.atEnd ? RoundCorner.CornerEnum.BottomLeft : RoundCorner.CornerEnum.TopLeft)
                : (root.atEnd ? RoundCorner.CornerEnum.BottomRight : RoundCorner.CornerEnum.TopRight)
        }

        DockWidgetRow {
            id: row
            inDock: false
            widgets: root.widgets
            anchors {
                top: root.vertical ? undefined : parent.top
                bottom: root.vertical ? undefined : parent.bottom
                left: root.vertical ? parent.left : undefined
                right: root.vertical ? parent.right : undefined
                horizontalCenter: root.vertical ? undefined : parent.horizontalCenter
                verticalCenter: root.vertical ? parent.verticalCenter : undefined
            }
        }
    }
}
