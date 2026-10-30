pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common.functions

Singleton {
    property string position: Config.options.dock.position ?? "bottom"
    readonly property bool vertical: position !== "bottom"

    function mTop(inner, outer, alongStart) {
        return vertical ? (alongStart ?? 0) : inner;
    }

    function mBottom(inner, outer, alongEnd) {
        return vertical ? (alongEnd ?? 0) : outer;
    }

    function mLeft(inner, outer, alongStart) {
        return vertical ? (position === "left" ? outer : inner) : (alongStart ?? 0);
    }

    function mRight(inner, outer, alongEnd) {
        return vertical ? (position === "left" ? inner : outer) : (alongEnd ?? 0);
    }

    readonly property real padding: 5
    readonly property real spacing: 3
    readonly property real backgroundPadding: 5
    readonly property real buttonSize: iconSize + 13
    readonly property real buttonSpacing: 1
    readonly property real defaultIconSize: 33
    readonly property real iconSize: Config.options.dock.iconSize
    readonly property real iconSpacing: Config.options.dock.iconSpacing
    readonly property real buttonBase: iconSize + 17
    readonly property real iconInset: padding + 8
    readonly property real appsButtonInnerInset: padding + 10
    readonly property real appsButtonOuterInset: padding + 7
    readonly property real pinButtonSize: 35
    readonly property real pinnedInnerMargin: 2
    readonly property real mediaInnerMargin: 12
    readonly property real mediaOuterMargin: 8
    readonly property real pinInnerMargin: 3
    readonly property real buttonInnerMargin: Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut
    readonly property string style: Config.options.dock.style ?? "float"
    readonly property bool hug: style === "hug"
    readonly property bool panel: style === "panel"
    // Islands: every group of items gets its own background; M3 islands are pill-shaped with tonal widgets.
    readonly property bool islands: style === "islands" || style === "m3"
    readonly property bool material: style === "m3"
    // Touches the screen edge instead of floating a gap away from it.
    readonly property bool flush: hug || panel
    readonly property real islandGap: 8
    // M3 islands are flat pills that hug the buttons, like the bar's M3 style.
    // The layouts keep the buttons at the dock's full thickness and push them by their
    // top/left margin, so the buttons' backgrounds span bandStart..bandEnd from the
    // window's top/left edge.
    readonly property real materialPillPadding: 4
    readonly property real leadingMargin: position === "left" ? 0 : pinnedInnerMargin
    readonly property real bandStart: leadingMargin + iconInset
    readonly property real bandEnd: leadingMargin + thickness - iconInset
    readonly property real materialLeadingMargin: bandStart - materialPillPadding
    readonly property real materialTrailingMargin: thickness - bandEnd - materialPillPadding
    readonly property real materialEdgeMargin: position === "left" ? materialLeadingMargin : materialTrailingMargin
    readonly property real materialInnerMargin: position === "left" ? materialTrailingMargin : materialLeadingMargin
    readonly property color materialPillColor: (Config.options.dock.followFrameColor && Config.options.bar.showFrame)
        ? Appearance.getColorFromName(Config.options.bar.frameColor)
        : Appearance.colors.colUiBackground
    readonly property bool magnifying: position === "bottom" && Config.options.dock.magnify
    readonly property real magnification: Math.max(1, Math.min(2.2, Config.options.dock.magnification ?? 1.2))
    readonly property real headroom: magnifying ? Math.ceil((magnification - 1) * (iconSize + 14)) + 6 : 0
    readonly property real thickness: (Config.options.dock.height ?? 70) + (iconSize - defaultIconSize) + Appearance.sizes.elevationMargin + Appearance.sizes.hyprlandGapsOut
    readonly property real activeSpacing: -4
    readonly property real mediaLength: 240
    readonly property real dotWidth: 10
    readonly property real dotHeight: 4
    readonly property real dotSpacing: 3
    readonly property real dotsGap: 2
    readonly property real dotsSideGap: 5
    readonly property real windowGap: Appearance.sizes.hyprlandGapsOut
    readonly property real separatorInnerMargin: Appearance.sizes.elevationMargin + padding + Appearance.rounding.normal - 4
    readonly property real separatorOuterMargin: Appearance.sizes.hyprlandGapsOut + padding + Appearance.rounding.normal
    readonly property real separatorInset: Appearance.sizes.elevationMargin + padding + Appearance.rounding.normal
    readonly property real zone: thickness - Appearance.sizes.elevationMargin - (flush ? Appearance.sizes.hyprlandGapsOut : 0) + windowGap

    // Eye candy
    readonly property var options: Config.options.dock
    readonly property real backgroundOpacity: Math.max(0, Math.min(1, options.backgroundOpacity ?? 1))
    readonly property string backgroundStyle: options.backgroundStyle ?? "solid"
    readonly property string borderStyle: options.borderStyle ?? "solid"
    readonly property string shadowStyle: options.shadowStyle ?? "none"
    readonly property string indicatorStyle: options.indicatorStyle ?? "pills"
    readonly property string hoverEffect: options.hoverEffect ?? "highlight"
    readonly property bool pressEffect: options.pressEffect ?? false
    readonly property string launchAnimation: options.launchAnimation ?? "bounce"
    readonly property bool highlightActive: options.highlightActive ?? false
    readonly property bool iconShadow: options.iconShadow ?? false
    readonly property bool reflection: (options.reflection ?? false) && !vertical
    readonly property string separatorStyle: options.separatorStyle ?? "line"
    readonly property string revealAnimation: options.revealAnimation ?? "slide"

    function indicatorColor(active) {
        const name = options.indicatorColor ?? "auto";
        if (name === "auto")
            return active ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4);
        const color = Appearance.getColorFromName(name);
        return active ? color : ColorUtils.transparentize(color, 0.45);
    }
}
