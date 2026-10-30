import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Io
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import qs.modules.ii.dock.widgets

Scope {
    id: root
    property bool pinned: Config.options?.dock.pinnedOnStartup ?? false
    property bool barState: false
    property bool ready: false

    // The start menu sits above the dock unless the dock reserves its space
    onPinnedChanged: GlobalStates.dockPinned = root.pinned

    Component.onCompleted: {
        DockStyle.position = Config.options.dock.position
        GlobalStates.dockPinned = root.pinned
        barSettleTimer.start()
    }

    Timer {
        id: barSettleTimer
        interval: 300
        onTriggered: {
            root.barState = GlobalStates.barOpen
            DockStyle.position = Config.options.dock.position
            root.ready = true
        }
    }

    Connections {
        target: Config.options.dock
        function onPositionChanged() {
            root.ready = false
            barSettleTimer.restart()
        }
    }

    Connections {
        target: GlobalStates
        function onBarOpenChanged() { barSettleTimer.restart() }
    }

    Variants {
        model: !root.ready ? [] : Quickshell.screens.map(screen => ({
            screen: screen,
            position: DockStyle.position,
            // Rebuilt when these change; magnification changes the window's height and anchoring
            layout: `${DockStyle.position}|${Config.options.dock.style}|${Config.options.dock.height}|${root.barState}|${DockStyle.magnifying}`
        }))

        PanelWindow {
            id: dockRoot
            required property var modelData
            screen: modelData.screen
            visible: !GlobalStates.screenLocked

            readonly property bool macos: DockStyle.magnifying
            readonly property bool hug: Config.options.dock.style === "hug"
            readonly property string position: modelData.position
            readonly property bool vertical: position !== "bottom"
            readonly property real gap: Appearance.sizes.hyprlandGapsOut
            readonly property real shadowMargin: Appearance.sizes.elevationMargin
            readonly property color backgroundColor: (DockStyle.flush && Config.options.dock.followFrameColor && Config.options.bar.showFrame)
                ? Appearance.getColorFromName(Config.options.bar.frameColor)
                : Appearance.getColorFromName(Config.options.dock.backgroundColor)
            readonly property real borderWidth: (Config.options.dock.showBackground && Config.options.dock.showBorder && !hug) ? Config.options.dock.borderWidth : 0
            // Glass is see-through by design; Hyprland blurs what's behind it.
            readonly property color backgroundFill: ColorUtils.transparentize(dockRoot.backgroundColor,
                1 - DockStyle.backgroundOpacity * (DockStyle.backgroundStyle === "glass" ? 0.55 : 1))
            readonly property color backgroundTinted: ColorUtils.mix(dockRoot.backgroundFill,
                ColorUtils.applyAlpha(Appearance.colors.colPrimary, Qt.color(dockRoot.backgroundFill).a), 0.72)
            property real revealProgress: dockRoot.reveal ? 1 : 0
            Behavior on revealProgress {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration * 1.5
                    easing.type: Easing.OutCubic
                }
            }

            property var monitor: WM.monitorFor(modelData.screen)
            property bool fullscreenOnThisMonitor: WM.fullscreenOnMonitor(monitor?.name)

            property bool reveal: {
                if (dockContextMenu.isOpen || trashButton.popupOpen || downloadsButton.holdOpen
                        || startWidgets.holdOpen || endWidgets.holdOpen || leftCorner.holdOpen || rightCorner.holdOpen)
                    return true
                // Like a taskbar under its start menu
                if (GlobalStates.startMenuOpen && GlobalStates.startMenuScreen === dockRoot.screen?.name)
                    return true
                if (fullscreenOnThisMonitor)
                    return Config.options?.dock.hoverToReveal && dockMouseArea.containsMouse
                return root.pinned
                    || (Config.options?.dock.hoverToReveal && (dockMouseArea.containsMouse || leftCorner.containsMouse || rightCorner.containsMouse
                        || GlobalStates.isFrameHovered(dockRoot.screen?.name, dockRoot.position)))
                    || activeApps.requestDockShow
                    || dragSlots.requestDockShow
                    || (!ToplevelManager.activeToplevel?.activated)
            }

            exclusiveZone: (root.pinned && !fullscreenOnThisMonitor)
                ? DockStyle.zone
                : 0

            anchors {
                top: dockRoot.vertical
                bottom: true
                left: dockRoot.position !== "right"
                right: dockRoot.position !== "left"
            }
            margins {
                bottom: DockStyle.flush && dockRoot.position === "bottom" ? -dockRoot.gap : 0
                left: DockStyle.flush && dockRoot.position === "left" ? -dockRoot.gap : 0
                right: DockStyle.flush && dockRoot.position === "right" ? -dockRoot.gap : 0
            }
            implicitWidth: dockRoot.vertical ? DockStyle.thickness : dockBackground.implicitWidth
            implicitHeight: dockRoot.vertical ? dockBackground.implicitHeight : DockStyle.thickness + DockStyle.headroom
            WlrLayershell.namespace: "quickshell:dock"
            color: "transparent"

            mask: Region {
                item: dockMouseArea
                Region { item: riseArea }
                Region { item: leftCorner }
                Region { item: rightCorner }
            }

            // Islands style: each run of items between separators gets its own background,
            // as {start, end} along the dock in dockBackground coordinates.
            readonly property var islandSpans: {
                if (!DockStyle.islands) return [];
                const magnified = !dockRoot.vertical && DockMagnify.window === dockRoot && DockMagnify.layout.length > 0;
                const rowStart = dockRoot.vertical ? dockRow.y : dockRow.x;
                const origin = magnified ? dockRow.mapToItem(null, 0, 0).x : 0;
                const shifted = at => rowStart + at + (magnified ? DockMagnify.offsetAt(origin + at) : 0);
                const spans = [];
                let current = null;
                for (const child of dockRow.children) {
                    if (!child.visible) continue;
                    if (child.isDockSeparator) {
                        if (child.splitsIsland) current = null;
                        continue;
                    }
                    const start = dockRoot.vertical ? child.y : child.x;
                    const length = dockRoot.vertical ? child.height : child.width;
                    if (length <= 0) continue;
                    if (current) {
                        current.end = shifted(start + length);
                    } else {
                        current = { start: shifted(start), end: shifted(start + length) };
                        spans.push(current);
                    }
                }
                return spans;
            }

            readonly property bool magnifyHover: DockStyle.magnifying && (dockMouseArea.containsMouse || riseArea.containsMouse)
            property real magnifyAmp: dockRoot.magnifyHover ? 1 : 0

            Behavior on magnifyAmp {
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }

            onMagnifyAmpChanged: {
                if (DockMagnify.window === dockRoot) DockMagnify.amplitude = dockRoot.magnifyAmp;
            }

            function updatePointer(item, mouseX) {
                if (!DockStyle.magnifying) return;
                DockMagnify.window = dockRoot;
                DockMagnify.amplitude = dockRoot.magnifyAmp;
                DockMagnify.pointer = item.mapToItem(null, mouseX, 0).x;
            }

            MouseArea {
                id: riseArea
                enabled: DockStyle.magnifying
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                x: dockMouseArea.x
                width: dockMouseArea.width
                height: DockStyle.headroom * dockRoot.magnifyAmp
                anchors.bottom: dockMouseArea.top
                onPositionChanged: mouse => dockRoot.updatePointer(riseArea, mouse.x)
                onEntered: dockRoot.updatePointer(riseArea, mouseX)
            }

            MouseArea {
                id: dockMouseArea
                hoverEnabled: true
                onPositionChanged: mouse => dockRoot.updatePointer(dockMouseArea, mouse.x)
                onEntered: dockRoot.updatePointer(dockMouseArea, mouseX)
                width: dockRoot.vertical || DockStyle.panel ? parent.width : implicitWidth
                height: dockRoot.vertical ? (DockStyle.panel ? parent.height : implicitHeight) : (dockRoot.macos ? DockStyle.thickness : parent.height)
                implicitWidth: dockHoverRegion.implicitWidth + dockRoot.shadowMargin * 2
                implicitHeight: dockHoverRegion.implicitHeight + dockRoot.shadowMargin * 2

                readonly property real hiddenOffset: Config.options?.dock.hoverToReveal
                    ? (DockStyle.thickness - Config.options.dock.hoverRegionHeight - (DockStyle.flush ? dockRoot.gap : 0))
                    : (DockStyle.thickness + 1)
                property real offset: dockRoot.reveal ? 0 : hiddenOffset

                Behavior on offset {
                    NumberAnimation {
                        alwaysRunToEnd: true
                        readonly property bool spring: DockStyle.revealAnimation === "spring"
                        duration: spring ? Appearance.animation.elementMove.duration : Appearance.animation.elementMoveFast.duration
                        easing.type: spring ? Easing.OutBack : Appearance.animation.elementMoveFast.type
                        easing.overshoot: 1.6
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }

                anchors {
                    top: dockRoot.vertical || dockRoot.macos ? undefined : parent.top
                    topMargin: dockMouseArea.offset
                    bottom: dockRoot.macos ? parent.bottom : undefined
                    bottomMargin: dockRoot.macos ? -dockMouseArea.offset : 0
                    horizontalCenter: dockRoot.vertical ? undefined : parent.horizontalCenter
                    verticalCenter: dockRoot.vertical ? parent.verticalCenter : undefined
                    left: dockRoot.position === "left" ? parent.left : undefined
                    leftMargin: -dockMouseArea.offset
                    right: dockRoot.position === "right" ? parent.right : undefined
                    rightMargin: -dockMouseArea.offset
                }

                Item {
                    id: dockHoverRegion
                    anchors.fill: parent
                    implicitWidth: dockBackground.implicitWidth
                    implicitHeight: dockBackground.implicitHeight
                    opacity: DockStyle.revealAnimation === "fade" || DockStyle.revealAnimation === "zoom" ? dockRoot.revealProgress : 1
                    scale: DockStyle.revealAnimation === "zoom" ? 0.8 + 0.2 * dockRoot.revealProgress : 1
                    transformOrigin: dockRoot.position === "left" ? Item.Left : dockRoot.position === "right" ? Item.Right : Item.Bottom

                    DockSurface {
                        visible: DockStyle.panel
                        anchors.fill: parent
                        anchors.topMargin: dockRoot.position === "bottom" ? dockRoot.shadowMargin : 0
                        anchors.leftMargin: dockRoot.position === "right" ? dockRoot.shadowMargin : 0
                        anchors.rightMargin: dockRoot.position === "left" ? dockRoot.shadowMargin : 0
                        fill: dockRoot.backgroundFill
                        tint: dockRoot.backgroundTinted
                        borderWidth: dockRoot.borderWidth
                        animate: dockRoot.reveal && dockRoot.visible
                    }

                    Item {
                        id: dockBackground
                        anchors {
                            top: dockRoot.vertical ? undefined : parent.top
                            bottom: dockRoot.vertical ? undefined : parent.bottom
                            left: dockRoot.vertical ? parent.left : undefined
                            right: dockRoot.vertical ? parent.right : undefined
                            horizontalCenter: dockRoot.vertical ? undefined : parent.horizontalCenter
                            verticalCenter: dockRoot.vertical ? parent.verticalCenter : undefined
                        }
                        implicitWidth: dockRow.implicitWidth + DockStyle.backgroundPadding * 2
                        implicitHeight: dockRow.implicitHeight + DockStyle.backgroundPadding * 2

                        DockSurface {
                            id: dockVisualBackground
                            visible: !DockStyle.islands && !DockStyle.panel
                            anchors.fill: parent
                            anchors.topMargin: dockRoot.position === "bottom" ? dockRoot.shadowMargin : 0
                            anchors.bottomMargin: dockRoot.position === "bottom" ? dockRoot.gap : 0
                            anchors.leftMargin: dockRoot.macos ? -DockMagnify.totalExtra / 2 : (dockRoot.position === "left" ? dockRoot.gap : dockRoot.position === "right" ? dockRoot.shadowMargin : 0)
                            anchors.rightMargin: dockRoot.macos ? -DockMagnify.totalExtra / 2 : (dockRoot.position === "right" ? dockRoot.gap : dockRoot.position === "left" ? dockRoot.shadowMargin : 0)
                            fill: dockRoot.backgroundFill
                            tint: dockRoot.backgroundTinted
                            borderWidth: dockRoot.borderWidth
                            animate: dockRoot.reveal && dockRoot.visible
                            radius: Config.options.dock.radius
                            topLeftRadius: dockRoot.hug && dockRoot.position === "left" ? 0 : radius
                            bottomLeftRadius: dockRoot.hug && (dockRoot.position === "left" || dockRoot.position === "bottom") ? 0 : radius
                            topRightRadius: dockRoot.hug && dockRoot.position === "right" ? 0 : radius
                            bottomRightRadius: dockRoot.hug && (dockRoot.position === "right" || dockRoot.position === "bottom") ? 0 : radius
                        }

                        Repeater {
                            // Count only, so magnifying moves the islands instead of rebuilding them
                            model: dockRoot.islandSpans.length
                            delegate: DockSurface {
                                required property int index
                                readonly property var span: dockRoot.islandSpans[index] ?? { start: 0, end: 0 }
                                readonly property real pad: DockStyle.backgroundPadding
                                // Distance from the screen edge and from the inner side, across the dock
                                readonly property real edgeMargin: DockStyle.material ? DockStyle.materialEdgeMargin : dockRoot.gap
                                readonly property real innerMargin: DockStyle.material ? DockStyle.materialInnerMargin : dockRoot.shadowMargin
                                x: dockRoot.vertical ? (dockRoot.position === "left" ? edgeMargin : innerMargin) : span.start - pad
                                y: dockRoot.vertical ? span.start - pad : innerMargin
                                width: dockRoot.vertical ? parent.width - edgeMargin - innerMargin : span.end - span.start + pad * 2
                                height: dockRoot.vertical ? span.end - span.start + pad * 2 : parent.height - edgeMargin - innerMargin
                                flat: DockStyle.material
                                fill: DockStyle.material ? DockStyle.materialPillColor : dockRoot.backgroundFill
                                tint: dockRoot.backgroundTinted
                                borderWidth: dockRoot.borderWidth
                                animate: dockRoot.reveal && dockRoot.visible
                                radius: DockStyle.material ? Appearance.rounding.full : Config.options.dock.radius
                            }
                        }

                        RoundCorner {
                            visible: dockRoot.hug && Config.options.dock.showBackground
                            anchors.right: dockRoot.vertical ? (dockRoot.position === "right" ? dockVisualBackground.right : undefined) : dockVisualBackground.left
                            anchors.bottom: dockRoot.vertical ? dockVisualBackground.top : dockVisualBackground.bottom
                            anchors.left: dockRoot.position === "left" ? dockVisualBackground.left : undefined
                            implicitSize: Appearance.rounding.screenRounding
                            color: dockRoot.backgroundFill
                            corner: dockRoot.position === "left" ? RoundCorner.CornerEnum.BottomLeft : RoundCorner.CornerEnum.BottomRight
                        }

                        RoundCorner {
                            visible: dockRoot.hug && Config.options.dock.showBackground
                            anchors.left: dockRoot.vertical ? (dockRoot.position === "left" ? dockVisualBackground.left : undefined) : dockVisualBackground.right
                            anchors.bottom: dockRoot.vertical ? undefined : dockVisualBackground.bottom
                            anchors.top: dockRoot.vertical ? dockVisualBackground.bottom : undefined
                            anchors.right: dockRoot.position === "right" ? dockVisualBackground.right : undefined
                            implicitSize: Appearance.rounding.screenRounding
                            color: dockRoot.backgroundFill
                            corner: dockRoot.position === "left" ? RoundCorner.CornerEnum.TopLeft
                                : dockRoot.position === "right" ? RoundCorner.CornerEnum.TopRight
                                : RoundCorner.CornerEnum.BottomLeft
                        }

                        DockContextMenu {
                            id: dockContextMenu
                            screen: dockRoot.screen
                        }

                        GridLayout {
                            id: dockRow
                            anchors.top: dockRoot.vertical ? undefined : parent.top
                            anchors.bottom: dockRoot.vertical ? undefined : parent.bottom
                            anchors.left: dockRoot.vertical ? parent.left : undefined
                            anchors.right: dockRoot.vertical ? parent.right : undefined
                            anchors.horizontalCenter: dockRoot.vertical ? undefined : parent.horizontalCenter
                            anchors.verticalCenter: dockRoot.vertical ? parent.verticalCenter : undefined
                            columns: dockRoot.vertical ? 1 : -1
                            rowSpacing: DockStyle.spacing
                            columnSpacing: DockStyle.spacing
                            property bool hasPinnedApps: (Config.options?.dock.pinnedApps?.length ?? 0) > 0
                            // Groups in order; a separator goes between two that are showing
                            readonly property var groups: [
                                startWidgets.length > 0,
                                Config.options.dock.showLaunchpadButton,
                                Config.options.dock.showPinButton,
                                dockRow.hasPinnedApps,
                                activeApps.activeUnpinned.length > 0 || (Config.options.dock.showMedia && activeApps.media.hasTrack),
                                endWidgets.length > 0,
                                Config.options.dock.showDownloadsButton || Config.options.dock.showTrashButton
                            ]
                            // Start button, pin button, pinned and open apps share the main island
                            readonly property var mainGroups: [1, 2, 3, 4]

                            function separatorBefore(group) {
                                return dockRow.groups[group] && dockRow.groups.slice(0, group).some(shown => shown);
                            }

                            // Inside the main island a separator is a divider; elsewhere it splits islands
                            function separatorSplits(group) {
                                let previous = group - 1;
                                while (previous >= 0 && !dockRow.groups[previous]) previous--;
                                return !(dockRow.mainGroups.includes(previous) && dockRow.mainGroups.includes(group));
                            }

                            DockWidgetRow {
                                id: startWidgets
                                widgets: Config.options.dock.widgets.start
                            }

                            DockSeparator {
                                visible: dockRow.separatorBefore(1)
                                splitsIsland: dockRow.separatorSplits(1)
                            }

                            StartButton {
                                id: startButton
                                inDock: true
                                toneName: "primaryContainer"
                                visible: Config.options.dock.showLaunchpadButton
                                Layout.topMargin: DockStyle.mTop(DockStyle.pinnedInnerMargin, 0)
                                Layout.bottomMargin: DockStyle.mBottom(DockStyle.pinnedInnerMargin, 0)
                                Layout.leftMargin: DockStyle.mLeft(DockStyle.pinnedInnerMargin, 0)
                                Layout.rightMargin: DockStyle.mRight(DockStyle.pinnedInnerMargin, 0)
                            }

                            DockSeparator {
                                visible: dockRow.separatorBefore(2)
                                splitsIsland: dockRow.separatorSplits(2)
                            }

                            DockPinButton {
                                pinned: root.pinned
                                onToggled: root.pinned = !root.pinned
                            }

                            DockSeparator {
                                visible: dockRow.separatorBefore(3)
                                splitsIsland: dockRow.separatorSplits(3)
                            }

                            DragApps {
                                id: dragSlots
                                visible: dockRow.hasPinnedApps
                                Layout.topMargin: DockStyle.mTop(DockStyle.pinnedInnerMargin, 0)
                                Layout.leftMargin: DockStyle.mLeft(DockStyle.pinnedInnerMargin, 0)
                                contextMenu: dockContextMenu
                                pinnedApps: Config.options?.dock.pinnedApps ?? []
                            }

                            DockSeparator {
                                visible: dockRow.separatorBefore(4)
                                splitsIsland: dockRow.separatorSplits(4)
                            }

                            DockActiveApps {
                                id: activeApps
                                contextMenu: dockContextMenu
                            }

                            DockSeparator {
                                visible: dockRow.separatorBefore(5)
                                splitsIsland: dockRow.separatorSplits(5)
                            }

                            DockWidgetRow {
                                id: endWidgets
                                widgets: Config.options.dock.widgets.end
                            }

                            DockSeparator {
                                visible: dockRow.separatorBefore(6)
                                splitsIsland: dockRow.separatorSplits(6)
                            }

                            Downloads {
                                id: downloadsButton
                                inDock: true
                                visible: Config.options.dock.showDownloadsButton
                                Layout.topMargin: DockStyle.mTop(DockStyle.pinnedInnerMargin, 0)
                                Layout.bottomMargin: DockStyle.mBottom(DockStyle.pinnedInnerMargin, 0)
                                Layout.leftMargin: DockStyle.mLeft(DockStyle.pinnedInnerMargin, 0)
                                Layout.rightMargin: DockStyle.mRight(DockStyle.pinnedInnerMargin, 0)
                            }

                            DockTrashButton {
                                id: trashButton
                            }
                        }
                    }
                }
            }

            DockCorner {
                id: leftCorner
                widgets: Config.options.dock.widgets.left
                offset: dockMouseArea.offset
                revealProgress: dockRoot.revealProgress
                fill: dockRoot.backgroundFill
                tint: dockRoot.backgroundTinted
                borderWidth: dockRoot.borderWidth
                animate: dockRoot.reveal && dockRoot.visible
            }

            DockCorner {
                id: rightCorner
                atEnd: true
                widgets: Config.options.dock.widgets.right
                offset: dockMouseArea.offset
                revealProgress: dockRoot.revealProgress
                fill: dockRoot.backgroundFill
                tint: dockRoot.backgroundTinted
                borderWidth: dockRoot.borderWidth
                animate: dockRoot.reveal && dockRoot.visible
            }
        }
    }
}
