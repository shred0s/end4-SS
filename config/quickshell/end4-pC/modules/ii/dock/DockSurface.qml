import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Qt5Compat.GraphicalEffects

/**
 * The dock's background: fill (solid, gradient or glass), border (solid,
 * gradient or animated) and shadow. Used for the dock itself, each island and
 * the corner widget islands.
 */
Item {
    id: root

    property color fill: "transparent"
    // Far end of the gradient style, away from the screen edge
    property color tint: fill
    property real radius: 0
    property real topLeftRadius: radius
    property real topRightRadius: radius
    property real bottomLeftRadius: radius
    property real bottomRightRadius: radius
    property real borderWidth: 0
    property color borderColor: Appearance.getColorFromName(Config.options.dock.borderColor)
    property bool shadow: DockStyle.shadowStyle !== "none"
    // Animated border keeps turning only while this is true
    property bool animate: true
    // Plain fill only: no shadow, border, gradient or glass (M3 islands)
    property bool flat: false
    readonly property alias body: body

    StyledRectangularShadow {
        target: body
        visible: root.shadow && Config.options.dock.showBackground && !root.flat
        readonly property bool glow: DockStyle.shadowStyle === "glow"
        blur: (glow ? 1.6 : 0.9) * Appearance.sizes.elevationMargin
        spread: glow ? 2 : 1
        offset: Qt.vector2d(0.0, glow ? 0.0 : 1.0)
        color: glow ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.45) : Appearance.colors.colShadow
    }

    Rectangle {
        id: body
        anchors.fill: parent
        color: Config.options.dock.showBackground && (root.flat || DockStyle.backgroundStyle !== "gradient") ? root.fill : "transparent"
        border.width: DockStyle.borderStyle === "solid" && !root.flat ? root.borderWidth : 0
        border.color: root.borderColor
        radius: root.radius
        topLeftRadius: root.topLeftRadius
        topRightRadius: root.topRightRadius
        bottomLeftRadius: root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius

        // Accent-tinted away from the screen edge, plain at the edge
        Rectangle {
            anchors.fill: parent
            visible: Config.options.dock.showBackground && DockStyle.backgroundStyle === "gradient" && !root.flat
            topLeftRadius: parent.topLeftRadius
            topRightRadius: parent.topRightRadius
            bottomLeftRadius: parent.bottomLeftRadius
            bottomRightRadius: parent.bottomRightRadius
            gradient: Gradient {
                orientation: DockStyle.vertical ? Gradient.Horizontal : Gradient.Vertical
                GradientStop {
                    position: 0
                    color: DockStyle.position === "left" ? root.fill : root.tint
                }
                GradientStop {
                    position: 1
                    color: DockStyle.position === "left" ? root.tint : root.fill
                }
            }
        }

        // Glass: a sheen across the top and a bright inner edge
        Rectangle {
            anchors.fill: parent
            anchors.margins: body.border.width
            visible: Config.options.dock.showBackground && DockStyle.backgroundStyle === "glass" && !root.flat
            topLeftRadius: Math.max(0, parent.topLeftRadius - anchors.margins)
            topRightRadius: Math.max(0, parent.topRightRadius - anchors.margins)
            bottomLeftRadius: Math.max(0, parent.bottomLeftRadius - anchors.margins)
            bottomRightRadius: Math.max(0, parent.bottomRightRadius - anchors.margins)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, Appearance.m3colors.darkmode ? 0.14 : 0.35)
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, Appearance.m3colors.darkmode ? 0.11 : 0.22) }
                GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.02) }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }

    // Gradient or slowly turning accent border, drawn through a ring mask
    Loader {
        anchors.fill: body
        active: root.borderWidth > 0 && DockStyle.borderStyle !== "solid" && !root.flat
        sourceComponent: Item {
            id: fancyBorder
            readonly property bool animated: DockStyle.borderStyle === "animated"

            Rectangle {
                id: borderRing
                anchors.fill: parent
                visible: false
                color: "transparent"
                radius: body.radius
                topLeftRadius: body.topLeftRadius
                topRightRadius: body.topRightRadius
                bottomLeftRadius: body.bottomLeftRadius
                bottomRightRadius: body.bottomRightRadius
                border.width: root.borderWidth
                border.color: "white"
            }

            LinearGradient {
                id: borderLinear
                anchors.fill: parent
                visible: false
                start: Qt.point(0, 0)
                end: Qt.point(width, height)
                gradient: Gradient {
                    GradientStop { position: 0; color: Appearance.colors.colPrimary }
                    GradientStop { position: 0.5; color: Appearance.colors.colTertiary }
                    GradientStop { position: 1; color: Appearance.colors.colSecondary }
                }
            }

            ConicalGradient {
                id: borderConical
                anchors.fill: parent
                visible: false
                gradient: Gradient {
                    GradientStop { position: 0; color: Appearance.colors.colPrimary }
                    GradientStop { position: 0.33; color: Appearance.colors.colTertiary }
                    GradientStop { position: 0.66; color: Appearance.colors.colSecondary }
                    GradientStop { position: 1; color: Appearance.colors.colPrimary }
                }
                NumberAnimation on angle {
                    running: fancyBorder.animated && root.animate && root.visible
                    from: 0
                    to: 360
                    duration: 6000
                    loops: Animation.Infinite
                }
            }

            OpacityMask {
                anchors.fill: parent
                source: fancyBorder.animated ? borderConical : borderLinear
                maskSource: borderRing
            }
        }
    }
}
