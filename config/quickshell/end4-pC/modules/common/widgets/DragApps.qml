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

Item {
    id: root

    property real btnSize: DockStyle.buttonSize
    property real btnSpacing: DockStyle.buttonSpacing + DockStyle.iconSpacing
    property real buttonPadding: DockStyle.padding
    property var pinnedApps: Config.options?.dock.pinnedApps ?? []
    property real maxWindowPreviewHeight: 200
    property real maxWindowPreviewWidth: 300
    property real windowControlsHeight: 30
    property Item lastHoveredButton: null
    property bool buttonHovered: false
    property bool requestDockShow: previewPopup.show
    property var contextMenu: null
    signal orderChanged(var newOrder)
    // Order shown while dragging; written to the config on drop.
    property var  _workOrder: []
    // One delegate per pinned app. This only changes when apps are pinned or
    // unpinned, so reordering moves existing delegates and they can slide.
    property var  _slotIds: []
    property bool _dragging: false

    function syncFromConfig() {
        if (root._dragging) return
        const ids = [...new Set(root.pinnedApps)]
        root._workOrder = ids
        const sameSet = root._slotIds.length === ids.length && ids.every(id => root._slotIds.includes(id))
        if (!sameSet) root._slotIds = ids
    }

    onPinnedAppsChanged: syncFromConfig()
    Component.onCompleted: syncFromConfig()

    readonly property real slotPitch: btnSize + btnSpacing
    readonly property real trackLength: _workOrder.length * btnSize + Math.max(0, _workOrder.length - 1) * btnSpacing

    Layout.fillHeight: false
    Layout.fillWidth: false
    implicitWidth:  DockStyle.vertical ? (parent?.width ?? btnSize) : trackLength
    implicitHeight: DockStyle.vertical ? trackLength : (parent?.height ?? btnSize)

    function popupCenterForButton(button) {
        if (!button || !root.QsWindow) return 0
        const point = root.QsWindow.mapFromItem(button, button.width / 2, button.height / 2)
        return DockStyle.vertical ? point.y : point.x
    }

    function moveSlot(appId, toPos) {
        const fromPos = _workOrder.indexOf(appId)
        toPos = Math.max(0, Math.min(_workOrder.length - 1, toPos))
        if (fromPos < 0 || fromPos === toPos) return
        let arr = _workOrder.slice()
        arr.splice(fromPos, 1)
        arr.splice(toPos, 0, appId)
        _workOrder = arr
    }

    function commitOrder() {
        const newOrder = _workOrder.slice()
        if (newOrder.join("\n") === root.pinnedApps.join("\n")) return
        Config.options.dock.pinnedApps = newOrder
        orderChanged(newOrder)
    }

    Repeater {
        id: slotRepeater
        model: root._slotIds

        delegate: Item {
            id: slotItem
            required property string modelData

            readonly property string appId: modelData
            readonly property int    slotIndex: Math.max(0, root._workOrder.indexOf(appId))
            property var    appEntry:  TaskbarApps.apps.find(a => a.appId === appId.toLowerCase()) ?? null
            property var    deskEntry: DesktopEntries.heuristicLookup(appId)
            property bool   appActive: appEntry?.toplevels?.find(t => t.activated) !== undefined
            readonly property int windowCount: appEntry?.toplevels?.length ?? 0
            property int    _lastFocused: -1

            Connections {
                target: DesktopEntries
                function onApplicationsChanged() {
                    slotItem.deskEntry = DesktopEntries.heuristicLookup(slotItem.appId)
                }
            }

            width:  DockStyle.vertical ? root.implicitWidth : root.btnSize
            height: DockStyle.vertical ? root.btnSize : root.implicitHeight
            x:      DockStyle.vertical ? 0 : slotIndex * root.slotPitch
            y:      DockStyle.vertical ? slotIndex * root.slotPitch : 0
            z:      dragHandler.active || settleAnim.running ? 1 : 0

            // The dragged slot jumps between positions as the order changes, so
            // only the others animate.
            Behavior on x {
                enabled: !dragHandler.active
                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
            }

            Behavior on y {
                enabled: !dragHandler.active
                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
            }

            // While dragging, the button follows the pointer: its offset from the
            // slot is where the drag started plus how far it moved, minus where
            // the slot is now. On drop it eases from there back into the slot.
            property real dragStartPos: 0
            property real lastDragOffset: 0
            property real settleOffset: 0
            readonly property real dragOffset: dragHandler.active
                ? dragStartPos + (DockStyle.vertical ? dragHandler.activeTranslation.y : dragHandler.activeTranslation.x)
                    - (DockStyle.vertical ? y : x)
                : 0
            onDragOffsetChanged: if (dragHandler.active) lastDragOffset = dragOffset

            NumberAnimation {
                id: settleAnim
                target: slotItem
                property: "settleOffset"
                to: 0
                duration: 260
                easing.type: Easing.OutCubic
            }

            Item {
                id: liftItem
                width: parent.width
                height: parent.height
                readonly property real offset: dragHandler.active ? slotItem.dragOffset : slotItem.settleOffset
                x: DockStyle.vertical ? 0 : offset
                y: DockStyle.vertical ? offset : 0

                scale: dragHandler.active ? 1.12 : 1
                Behavior on scale {
                    NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                }

                layer.enabled: dragHandler.active || settleAnim.running
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowVerticalOffset: 5
                    shadowBlur: 0.8
                    shadowColor: "#80000000"
                }

                DockButton {
                    id: dockBtn
                    anchors.fill: parent

                    property var appToplevel: slotItem.appEntry
                    magnifiable: true

                    innerInset: DockStyle.iconInset
                    outerInset: DockStyle.iconInset
                    Layout.topMargin: 0
                    Layout.leftMargin: 0

                    tooltipText: slotItem.deskEntry?.name ?? slotItem.appId
                    // Apps with windows get the preview popup instead.
                    tooltipEnabled: slotItem.windowCount === 0 && !root._dragging
                        && !(root.contextMenu?.isOpen ?? false)
                    scrollEnabled: slotItem.windowCount > 0
                    onScrolled: step => TaskbarApps.cycleWindows(slotItem.appEntry, step)

                    hoverEnabled: true
                    onHoveredChanged: {
                        if (hovered) {
                            root.lastHoveredButton = dockBtn
                            root.buttonHovered = true
                        } else {
                            root.buttonHovered = false
                        }
                    }

                    onClicked: {
                        const entry = slotItem.appEntry
                        if (!entry || entry.toplevels.length === 0) {
                            if (!slotItem.deskEntry) return
                            slotItem.deskEntry.execute()
                            TaskbarApps.noteLaunch(slotItem.appId)
                            return
                        }
                        const next = (slotItem._lastFocused + 1) % entry.toplevels.length
                        slotItem._lastFocused = next
                        entry.toplevels[next].activate()
                    }

                    middleClickAction: () => { slotItem.deskEntry?.execute() }
                    altAction:         () => { root.contextMenu?.open(dockBtn, slotItem.appId) }

                    contentItem: DockAppIcon {
                        anchors.centerIn: parent
                        iconSource: SystemAppearance.iconPath(AppSearch.guessIcon(slotItem.appId), "image-missing")
                        windowCount: slotItem.windowCount
                        active: slotItem.appActive
                        hovered: dockBtn.hovered && !dragHandler.active
                        pressed: dockBtn.down && !dragHandler.active
                        launching: slotItem.windowCount === 0 && TaskbarApps.isLaunching(slotItem.appId)
                    }
                }
            }

            DragHandler {
                id: dragHandler
                target: null
                grabPermissions: PointerHandler.CanTakeOverFromAnything

                onActiveChanged: {
                    if (active) {
                        settleAnim.stop()
                        slotItem.dragStartPos = DockStyle.vertical ? slotItem.y : slotItem.x
                        slotItem.lastDragOffset = 0
                        root._dragging = true
                        root.buttonHovered = false
                        return
                    }
                    slotItem.settleOffset = slotItem.lastDragOffset
                    settleAnim.restart()
                    root._dragging = false
                    root.commitOrder()
                }

                onActiveTranslationChanged: {
                    if (!active) return
                    const along = DockStyle.vertical ? activeTranslation.y : activeTranslation.x
                    root.moveSlot(slotItem.appId, Math.round((slotItem.dragStartPos + along) / root.slotPitch))
                }
            }
        }
    }

    PopupWindow {
        id: previewPopup
        property var appTopLevel: root.lastHoveredButton?.appToplevel ?? null

        property bool shouldShow: WM.compositor === "hyprland"
                                  && (popupMouseArea.containsMouse || root.buttonHovered)
                                  && !root._dragging
                                  && !(root.contextMenu?.isOpen ?? false)
                                  && Config.options.dock.showPreviews
                                  && appTopLevel
                                  && appTopLevel.toplevels
                                  && appTopLevel.toplevels.length > 0

        property bool show: false
        property real cachedCenter: 0
        readonly property real shiftX: DockStyle.position === "left" ? -12 : DockStyle.position === "right" ? 12 : 0
        readonly property real shiftY: DockStyle.vertical ? 0 : 12

        Connections {
            target: root
            function onLastHoveredButtonChanged() {
                if (root.lastHoveredButton && root.QsWindow)
                    previewPopup.cachedCenter = root.popupCenterForButton(root.lastHoveredButton)
            }
            function onButtonHoveredChanged() {
                if (root.buttonHovered && root.lastHoveredButton && root.QsWindow)
                    previewPopup.cachedCenter = root.popupCenterForButton(root.lastHoveredButton)
                updateTimer.restart()
            }
        }

        onShouldShowChanged: {
            updateTimer.restart()
        }

        onShowChanged: {
            if (show) {
                closeAnim.stop()
                openAnim.restart()
            } else {
                openAnim.stop()
                closeAnim.restart()
            }
        }

        ParallelAnimation {
            id: openAnim
            NumberAnimation {
                target: bodyScale
                properties: "xScale,yScale"
                from: 0.85
                to: 1
                duration: 220
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
            NumberAnimation {
                target: bodyShift
                property: "x"
                from: previewPopup.shiftX
                to: 0
                duration: 220
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
            NumberAnimation {
                target: bodyShift
                property: "y"
                from: previewPopup.shiftY
                to: 0
                duration: 220
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
            NumberAnimation {
                target: body
                property: "opacity"
                to: 1
                duration: 130
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
        }

        ParallelAnimation {
            id: closeAnim
            NumberAnimation {
                target: bodyScale
                properties: "xScale,yScale"
                to: 0.9
                duration: 110
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
            }
            NumberAnimation {
                target: bodyShift
                property: "x"
                to: previewPopup.shiftX * 0.6
                duration: 110
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
            }
            NumberAnimation {
                target: bodyShift
                property: "y"
                to: previewPopup.shiftY * 0.6
                duration: 110
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
            }
            NumberAnimation {
                target: body
                property: "opacity"
                to: 0
                duration: 90
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
            }
        }

        Timer {
            id: updateTimer
            interval: previewPopup.shouldShow ? 100 : 30
            onTriggered: {
                previewPopup.show = previewPopup.shouldShow
            }
        }

        anchor {
            window: root.QsWindow.window
            adjustment: PopupAdjustment.None
            gravity: DockStyle.position === "left" ? (Edges.Bottom | Edges.Right)
                : DockStyle.position === "right" ? (Edges.Bottom | Edges.Left)
                : (Edges.Top | Edges.Right)
            edges: Edges.Top | Edges.Left
            rect.x: DockStyle.position === "left"
                ? DockStyle.zone + Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
                : DockStyle.position === "right"
                    ? (root.QsWindow.window?.width ?? 0) - DockStyle.zone - Appearance.sizes.hyprlandGapsOut + Appearance.sizes.elevationMargin
                    : 0
        }

        visible: body.opacity > 0
        color: "transparent"
        implicitWidth: DockStyle.vertical ? popupMouseArea.implicitWidth : (root.QsWindow.window?.width ?? 1)
        implicitHeight: DockStyle.vertical
            ? (root.QsWindow.window?.height ?? 1)
            : popupMouseArea.implicitHeight + root.windowControlsHeight + Appearance.sizes.elevationMargin * 2

        MouseArea {
            id: popupMouseArea
            anchors.bottom: DockStyle.vertical ? undefined : parent.bottom
            anchors.left: DockStyle.position === "left" ? parent.left : undefined
            anchors.right: DockStyle.position === "right" ? parent.right : undefined
            implicitWidth:  popupBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
            implicitHeight: DockStyle.vertical
                ? popupBackground.implicitHeight + Appearance.sizes.elevationMargin * 2
                : root.maxWindowPreviewHeight + root.windowControlsHeight + Appearance.sizes.elevationMargin * 2
            hoverEnabled: true
            x: DockStyle.vertical ? 0 : previewPopup.cachedCenter - width / 2
            y: DockStyle.vertical
                ? Math.max(0, Math.min((root.QsWindow.window?.height ?? 0) - height, previewPopup.cachedCenter - height / 2))
                : 0

            Item {
                id: body
                anchors.fill: parent
                opacity: 0
                visible: opacity > 0
                transform: [
                    Scale {
                        id: bodyScale
                        origin.x: DockStyle.position === "left" ? Appearance.sizes.elevationMargin
                            : DockStyle.position === "right" ? body.width - Appearance.sizes.elevationMargin
                            : body.width / 2
                        origin.y: DockStyle.vertical ? body.height / 2 : body.height - Appearance.sizes.elevationMargin
                        xScale: 0.85
                        yScale: 0.85
                    },
                    Translate {
                        id: bodyShift
                    }
                ]

                StyledRectangularShadow {
                    target: popupBackground
                }

                Rectangle {
                    id: popupBackground
                    property real padding: 5
                    clip: true
                    color: Config.options.appearance.uiBackground === "oled" ? "#000000" : Appearance.m3colors.m3surfaceContainer
                    radius: Appearance.rounding.normal
                    anchors.bottom: DockStyle.vertical ? undefined : parent.bottom
                    anchors.bottomMargin: Appearance.sizes.elevationMargin
                    anchors.horizontalCenter: DockStyle.vertical ? undefined : parent.horizontalCenter
                    anchors.verticalCenter: DockStyle.vertical ? parent.verticalCenter : undefined
                    anchors.left: DockStyle.position === "left" ? parent.left : undefined
                    anchors.right: DockStyle.position === "right" ? parent.right : undefined
                    anchors.leftMargin: Appearance.sizes.elevationMargin
                    anchors.rightMargin: Appearance.sizes.elevationMargin
                    implicitHeight: previewRowLayout.implicitHeight + padding * 2
                    implicitWidth:  previewRowLayout.implicitWidth  + padding * 2
                    Behavior on implicitWidth {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on implicitHeight {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    RowLayout {
                        id: previewRowLayout
                        anchors.centerIn: parent

                        Repeater {
                            model: ScriptModel {
                                values: WM.compositor === "hyprland" ? (previewPopup.appTopLevel?.toplevels ?? []) : []
                            }

                            RippleButton {
                                id: windowButton
                                Layout.fillHeight: true
                                required property var modelData
                                padding: 0

                                middleClickAction: () => { windowButton.modelData?.close() }
                                onClicked: { windowButton.modelData?.activate() }

                                contentItem: ColumnLayout {
                                    implicitWidth:  screencopyView.implicitWidth
                                    implicitHeight: screencopyView.implicitHeight

                                    ButtonGroup {
                                        contentWidth: parent.width - anchors.margins * 2

                                        StyledText {
                                            Layout.margins: 5
                                            Layout.fillWidth: true
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            text: windowButton.modelData?.title
                                            elide: Text.ElideRight
                                            color: Appearance.m3colors.m3onSurface
                                        }

                                        GroupButton {
                                            id: closeButton
                                            colBackground: ColorUtils.transparentize(
                                                Appearance.colors.colSurfaceContainer)
                                            baseWidth:    root.windowControlsHeight
                                            baseHeight:   root.windowControlsHeight
                                            buttonRadius: Appearance.rounding.full
                                            contentItem: MaterialSymbol {
                                                anchors.centerIn: parent
                                                horizontalAlignment: Text.AlignHCenter
                                                text: "close"
                                                iconSize: Appearance.font.pixelSize.normal
                                                color: Appearance.m3colors.m3onSurface
                                            }
                                            onClicked: { windowButton.modelData?.close() }
                                        }
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        implicitHeight: screencopyView.height
                                        implicitWidth:  screencopyView.width

                                        ScreencopyView {
                                            id: screencopyView
                                            anchors.centerIn: parent
                                            captureSource: windowButton.modelData
                                            live: true
                                            paintCursor: true
                                            constraintSize: Qt.size(
                                                root.maxWindowPreviewWidth,
                                                root.maxWindowPreviewHeight)
                                            layer.enabled: true
                                            layer.effect: OpacityMask {
                                                maskSource: Rectangle {
                                                    width:  screencopyView.width
                                                    height: screencopyView.height
                                                    radius: Appearance.rounding.small
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

        }
    }
}
