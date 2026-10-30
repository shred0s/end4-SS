import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

RippleButton {
    id: root
    property real innerInset: 0
    property real outerInset: 0
    property bool magnifiable: false
    // Not scaled, but moved aside by magnified neighbours
    property bool followMagnify: false
    property int magnifyId: -1
    readonly property var magnifyValue: root.magnifyId >= 0 ? (DockMagnify.values[root.magnifyId] ?? null) : null
    readonly property bool magnifyActive: DockStyle.magnifying && root.magnifiable
    readonly property real naturalWidth: DockStyle.vertical
        ? implicitBackgroundWidth + leftInset + rightInset
        : implicitHeight - topInset - bottomInset

    Layout.fillHeight: !DockStyle.vertical
    Layout.fillWidth: DockStyle.vertical
    Layout.topMargin: DockStyle.mTop(DockStyle.buttonInnerMargin, 0)
    Layout.leftMargin: DockStyle.mLeft(DockStyle.buttonInnerMargin, 0)
    topInset: DockStyle.mTop(innerInset, outerInset)
    bottomInset: DockStyle.mBottom(innerInset, outerInset)
    leftInset: DockStyle.mLeft(innerInset, outerInset)
    rightInset: DockStyle.mRight(innerInset, outerInset)
    implicitWidth: naturalWidth
    buttonRadius: Appearance.rounding.normal
    // Other hover effects animate the icon itself instead of tinting the button.
    colBackgroundHover: DockStyle.hoverEffect === "highlight" ? Appearance.colors.colLayer1Hover : "transparent"

    transformOrigin: Item.Bottom
    scale: root.magnifyActive && root.magnifyValue ? root.magnifyValue.scale : 1
    z: root.magnifyActive && root.magnifyValue ? root.magnifyValue.scale : 0
    transform: Translate {
        x: root.magnifyActive && root.magnifyValue ? root.magnifyValue.shift
            : root.followMagnify && DockStyle.magnifying ? DockMagnify.shiftOf(root)
            : 0
    }


    // Magnifiable can change after creation (e.g. a widget joining a group)
    function updateMagnifyRegistration() {
        if (root.magnifiable && root.magnifyId < 0) {
            root.magnifyId = DockMagnify.register(root);
        } else if (!root.magnifiable && root.magnifyId >= 0) {
            DockMagnify.unregister(root.magnifyId);
            root.magnifyId = -1;
        }
    }
    onMagnifiableChanged: root.updateMagnifyRegistration()
    Component.onCompleted: root.updateMagnifyRegistration()
    Component.onDestruction: DockMagnify.unregister(root.magnifyId)

    background.implicitHeight: DockStyle.buttonBase
    background.implicitWidth: DockStyle.buttonBase

    property string tooltipText: ""
    property bool tooltipEnabled: true

    PopupToolTip {
        text: root.tooltipText
        extraVisibleCondition: root.tooltipEnabled && root.tooltipText !== ""
        verticalMargin: 8
        anchorEdges: DockStyle.position === "left" ? Edges.Right
            : DockStyle.position === "right" ? Edges.Left
            : Edges.Top
    }

    // One step per wheel notch; touchpads send many small deltas that add up.
    property bool scrollEnabled: false
    property real wheelAccumulator: 0
    signal scrolled(int step)

    WheelHandler {
        target: null
        enabled: root.scrollEnabled
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            root.wheelAccumulator += event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
            while (Math.abs(root.wheelAccumulator) >= 120) {
                const direction = root.wheelAccumulator > 0 ? 1 : -1;
                root.wheelAccumulator -= direction * 120;
                root.scrolled(-direction);
            }
        }
    }
}
