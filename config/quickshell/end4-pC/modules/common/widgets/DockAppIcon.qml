import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Widgets

Item {
    id: root

    property string iconSource: ""
    property int windowCount: 0
    property bool active: false
    property real iconSize: DockStyle.iconSize
    property bool monochrome: Config.options.dock.monochromeIcons
    // Set by the button that holds the icon, for the hover and press effects.
    property bool hovered: false
    property bool pressed: false
    // Bounces or pulses the icon while the app is starting.
    property bool launching: false
    property real bounceOffset: 0
    property real pulse: 0

    // Edge-aware helpers: icons move and grow away from the screen edge.
    readonly property real awayX: DockStyle.position === "left" ? 1 : DockStyle.position === "right" ? -1 : 0
    readonly property real awayY: DockStyle.vertical ? 0 : -1

    readonly property real hoverLift: root.hovered && DockStyle.hoverEffect === "lift" ? root.iconSize * 0.22 : 0
    readonly property real hoverScale: root.hovered && DockStyle.hoverEffect === "zoom" ? 1.18 : 1
    readonly property real pressScale: root.pressed && DockStyle.pressEffect ? 0.84 : 1

    property real liftOffset: root.hoverLift
    Behavior on liftOffset {
        NumberAnimation {
            duration: Appearance.animation.elementMoveSmall.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
        }
    }

    property real iconScale: root.hoverScale * root.pressScale
    Behavior on iconScale {
        NumberAnimation {
            duration: Appearance.animation.elementMoveSmall.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
        }
    }

    SequentialAnimation {
        running: root.launching && DockStyle.launchAnimation === "bounce"
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation {
            target: root
            property: "bounceOffset"
            to: root.iconSize * 0.4
            duration: 260
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: root
            property: "bounceOffset"
            to: 0
            duration: 260
            easing.type: Easing.InQuad
        }
        PauseAnimation { duration: 140 }
    }

    SequentialAnimation {
        running: root.launching && DockStyle.launchAnimation === "pulse"
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation {
            target: root
            property: "pulse"
            to: 1
            duration: 480
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: root
            property: "pulse"
            to: 0
            duration: 480
            easing.type: Easing.InOutSine
        }
    }

    // Pill behind the focused app
    Rectangle {
        anchors.centerIn: parent
        width: root.iconSize + 12
        height: root.iconSize + 12
        radius: Appearance.rounding.normal
        color: ColorUtils.transparentize(DockStyle.indicatorColor(true), 0.82)
        border.width: 1
        border.color: ColorUtils.transparentize(DockStyle.indicatorColor(true), 0.7)
        opacity: DockStyle.highlightActive && root.active ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    Item {
        id: iconBody
        anchors.fill: parent
        opacity: 1 - 0.45 * root.pulse
        transform: [
            Translate {
                readonly property real offset: root.bounceOffset + root.liftOffset
                x: root.awayX * offset
                y: root.awayY * offset
            },
            Scale {
                // Grow from the icon's edge nearest the screen edge.
                origin.x: iconStack.x + iconStack.width / 2 - root.awayX * iconStack.width / 2
                origin.y: iconStack.y + iconStack.height / 2 - root.awayY * iconStack.height / 2
                xScale: root.iconScale * (1 - 0.08 * root.pulse)
                yScale: xScale
            }
        ]

        // Soft glow behind the icon on hover
        RectangularShadow {
            anchors.centerIn: iconStack
            width: root.iconSize * 0.62
            height: width
            radius: width / 2
            blur: root.iconSize * 0.55
            spread: root.iconSize * 0.06
            color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.35)
            opacity: root.hovered && DockStyle.hoverEffect === "glow" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        Loader {
            active: DockStyle.iconShadow
            anchors.fill: iconStack
            sourceComponent: DropShadow {
                source: iconStack
                radius: 7
                samples: 15
                verticalOffset: DockStyle.vertical ? 0 : 2
                horizontalOffset: root.awayX * -2
                color: Appearance.colors.colShadow
                transparentBorder: true
            }
        }

        Item {
            id: iconStack
            anchors.centerIn: parent
            width: root.iconSize
            height: root.iconSize

            IconImage {
                id: iconImage
                anchors.fill: parent
                source: root.iconSource
                implicitSize: root.iconSize
            }

            Loader {
                active: root.monochrome
                anchors.fill: parent
                sourceComponent: Item {
                    Desaturate {
                        id: desaturatedIcon
                        visible: false
                        anchors.fill: parent
                        source: iconImage
                        desaturation: 0.8
                    }
                    ColorOverlay {
                        anchors.fill: desaturatedIcon
                        source: desaturatedIcon
                        color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.9)
                    }
                }
            }
        }

        // Shelf reflection, fading out away from the icon
        Loader {
            active: DockStyle.reflection
            anchors.top: iconStack.bottom
            anchors.topMargin: 1
            anchors.horizontalCenter: iconStack.horizontalCenter
            width: root.iconSize
            height: Math.round(root.iconSize * 0.38)
            sourceComponent: Item {
                clip: true
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: root.iconSize
                        height: Math.round(root.iconSize * 0.38)
                        gradient: Gradient {
                            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.32) }
                            GradientStop { position: 1; color: "transparent" }
                        }
                    }
                }

                ShaderEffectSource {
                    width: root.iconSize
                    height: root.iconSize
                    sourceItem: iconStack
                    transform: Scale {
                        origin.y: root.iconSize / 2
                        yScale: -1
                    }
                }
            }
        }
    }

    // Window indicators
    Item {
        id: indicators
        // Between the icon and the screen edge
        readonly property real gap: root.iconSize / 2
            + (DockStyle.vertical ? DockStyle.dotsSideGap + DockStyle.dotHeight / 2 : DockStyle.dotsGap)
        width: Math.max(1, indicatorLoader.item?.implicitWidth ?? 1)
        height: Math.max(1, indicatorLoader.item?.implicitHeight ?? 1)
        x: DockStyle.vertical ? parent.width / 2 - root.awayX * gap - width / 2 : (parent.width - width) / 2
        y: DockStyle.vertical ? (parent.height - height) / 2 : parent.height / 2 + gap
        visible: root.windowCount > 0 && DockStyle.indicatorStyle !== "none"

        Loader {
            id: indicatorLoader
            anchors.centerIn: parent
            sourceComponent: DockStyle.indicatorStyle === "line" ? lineIndicator
                : DockStyle.indicatorStyle === "glow" ? glowIndicator
                : DockStyle.indicatorStyle === "dots" ? dotsIndicator
                : pillsIndicator
        }
    }

    Component {
        id: pillsIndicator
        GridLayout {
            columns: DockStyle.vertical ? 1 : -1
            rowSpacing: DockStyle.dotSpacing
            columnSpacing: DockStyle.dotSpacing
            Repeater {
                model: Math.min(root.windowCount, 3)
                delegate: Rectangle {
                    readonly property real longSide: root.windowCount <= 3 ? DockStyle.dotWidth : DockStyle.dotHeight
                    radius: Appearance.rounding.full
                    implicitWidth: DockStyle.vertical ? DockStyle.dotHeight : longSide
                    implicitHeight: DockStyle.vertical ? longSide : DockStyle.dotHeight
                    color: DockStyle.indicatorColor(root.active)
                }
            }
        }
    }

    Component {
        id: dotsIndicator
        GridLayout {
            columns: DockStyle.vertical ? 1 : -1
            rowSpacing: DockStyle.dotSpacing
            columnSpacing: DockStyle.dotSpacing
            Repeater {
                model: Math.min(root.windowCount, 3)
                delegate: Rectangle {
                    radius: width / 2
                    implicitWidth: DockStyle.dotHeight + 1
                    implicitHeight: DockStyle.dotHeight + 1
                    color: DockStyle.indicatorColor(root.active)
                }
            }
        }
    }

    // One bar that is longer for the focused app and with more windows
    Component {
        id: lineIndicator
        Rectangle {
            readonly property real length: root.iconSize * (root.active ? 0.62 : 0.3) + Math.min(root.windowCount - 1, 3) * 3
            implicitWidth: DockStyle.vertical ? 3 : length
            implicitHeight: DockStyle.vertical ? length : 3
            radius: Appearance.rounding.full
            color: DockStyle.indicatorColor(root.active)
            Behavior on implicitWidth {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on implicitHeight {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }

    // A small bar of light with a bloom around it
    Component {
        id: glowIndicator
        Item {
            readonly property real length: root.iconSize * (root.active ? 0.5 : 0.24)
            implicitWidth: DockStyle.vertical ? 3 : length
            implicitHeight: DockStyle.vertical ? length : 3
            RectangularShadow {
                anchors.fill: glowCore
                radius: glowCore.radius
                blur: root.active ? 10 : 6
                spread: 1
                color: DockStyle.indicatorColor(root.active)
            }
            Rectangle {
                id: glowCore
                anchors.fill: parent
                radius: Appearance.rounding.full
                color: ColorUtils.mix(DockStyle.indicatorColor(root.active), "white", 0.7)
            }
        }
    }
}
