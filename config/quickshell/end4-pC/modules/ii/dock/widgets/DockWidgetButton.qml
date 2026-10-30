import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick

/**
 * Base for dock widgets. Square ones magnify like app icons when they're in
 * the dock; wide or grouped ones move aside instead. On M3 islands they get a
 * tonal pill, like the bar's M3 style. Widgets with a `popup` open it on click.
 * Text inside is drawn as curves (Text.CurveRendering), so it stays smooth
 * while the content is scaled.
 */
DockButton {
    id: root

    property bool inDock: false
    // Hidden from the row while false (e.g. no battery)
    property bool available: true
    // Keeps the dock revealed, e.g. while a menu from the widget is open
    property bool holdOpen: widgetPopup.isOpen
    // Opened on click, in place of a window or sidebar
    property Component popup: null
    readonly property bool popupOpen: widgetPopup.isOpen
    property bool wide: false
    // Something the widget switches on (night light, keep awake...): filled with the accent
    property bool active: false
    property string symbol: ""
    property bool symbolFill: false
    // Pill color on M3 islands, from DockWidgets ("none" for widgets that look like app icons)
    property string toneName: "secondaryContainer"
    readonly property string toneKey: root.toneName.charAt(0).toUpperCase() + root.toneName.slice(1)
    readonly property bool tonal: root.toneName !== "none"
    readonly property color tone: Appearance.colors[`col${root.toneKey}`] ?? Appearance.colors.colSecondaryContainer
    readonly property color toneContent: Appearance.colors[`colOn${root.toneKey}`] ?? Appearance.colors.colOnSecondaryContainer
    // first/middle/last when merged with its neighbours; the row draws the shared pill
    property string groupPosition: ""
    readonly property bool grouped: root.groupPosition !== ""
    readonly property bool material: DockStyle.material && root.tonal && !root.grouped
    // Content sits on a tonal pill, its own or its group's
    readonly property bool tonalSurface: DockStyle.material && root.tonal
    readonly property color contentColor: root.active ? Appearance.colors.colOnPrimary
        : root.tonalSurface ? root.toneContent
        : root.grouped ? Appearance.colors.colOnLayer2
        : Appearance.colors.colOnLayer0
    // Lift/zoom hover and press squish, like the other dock buttons
    readonly property real contentScale: root.down && DockStyle.pressEffect ? 0.84
        : root.hovered && (DockStyle.hoverEffect === "lift" || DockStyle.hoverEffect === "zoom") ? 1.12
        : 1
    property real animatedScale: root.contentScale
    Behavior on animatedScale {
        NumberAnimation {
            duration: Appearance.animation.elementMoveSmall.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
        }
    }

    function openPopup() {
        widgetPopup.open();
    }

    function closePopup() {
        widgetPopup.close();
    }

    tooltipEnabled: !widgetPopup.isOpen
    toggled: root.active || widgetPopup.isOpen
    onClicked: {
        if (root.popup) widgetPopup.toggle();
    }

    magnifiable: root.inDock && !root.wide && !root.grouped
    followMagnify: root.inDock && (root.wide || root.grouped)
    innerInset: DockStyle.iconInset
    outerInset: DockStyle.iconInset
    // Grouped icons sit a little closer together
    readonly property real slotLength: root.grouped ? Math.round(DockStyle.buttonBase * 0.8) : DockStyle.buttonBase
    implicitWidth: DockStyle.vertical ? naturalWidth
        : root.wide ? Math.max(root.slotLength, contentItem.implicitWidth + 20)
        : root.slotLength
    implicitHeight: Math.max(DockStyle.vertical ? root.slotLength : implicitBackgroundHeight + topInset + bottomInset,
        DockStyle.vertical && root.wide ? contentItem.implicitHeight + 16 : 0)
    buttonRadius: root.material || (root.grouped && DockStyle.material) ? Appearance.rounding.full : Appearance.rounding.normal
    colBackground: root.material ? root.tone : ColorUtils.transparentize(root.tone, 1)
    colBackgroundHover: root.material ? ColorUtils.mix(root.tone, root.toneContent, 0.88)
        : root.grouped ? ColorUtils.transparentize(root.contentColor, 0.88)
        : DockStyle.hoverEffect === "highlight" ? Appearance.colors.colLayer1Hover
        : "transparent"
    colRipple: root.material ? ColorUtils.mix(root.tone, root.toneContent, 0.76) : Appearance.colors.colLayer1Active
    // An open popup tints the button; an active state fills it with the accent
    colBackgroundToggled: root.active ? Appearance.colors.colPrimary
        : root.material ? ColorUtils.mix(root.tone, root.toneContent, 0.8)
        : Appearance.colors.colLayer1Active
    colBackgroundToggledHover: root.active ? Appearance.colors.colPrimaryHover : root.colBackgroundToggled

    // Off for content that animates itself (app-style icons)
    property bool scaleContent: true
    Binding {
        target: root.contentItem
        property: "scale"
        value: root.animatedScale
        when: root.scaleContent
    }

    DockWidgetPopup {
        id: widgetPopup
        button: root
        content: root.popup
    }

    contentItem: Item {
        implicitWidth: symbolItem.implicitWidth
        implicitHeight: symbolItem.implicitHeight

        MaterialSymbol {
            id: symbolItem
            anchors.centerIn: parent
            text: root.symbol
            fill: root.symbolFill ? 1 : 0
            iconSize: Math.round(DockStyle.iconSize * 0.72)
            color: root.contentColor
            renderType: Text.CurveRendering
        }
    }
}
