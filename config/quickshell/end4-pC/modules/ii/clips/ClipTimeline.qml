pragma ComponentBehavior: Bound
import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/*
 * Seek bar with trim handles. All values are in seconds.
 */
Item {
    id: root

    property real duration: 1
    property real position: 0
    property real trimStart: 0
    property real trimEnd: duration
    readonly property bool trimmed: trimStart > 0.05 || trimEnd < duration - 0.05

    signal seekRequested(real seconds)
    signal trimStartRequested(real seconds)
    signal trimEndRequested(real seconds)
    signal trimDragStarted()
    signal trimDragFinished()

    readonly property real handleWidth: 12
    readonly property real trackLeft: handleWidth
    readonly property real trackWidth: Math.max(1, width - handleWidth * 2)

    function xFor(seconds) {
        return trackLeft + trackWidth * Math.max(0, Math.min(1, seconds / Math.max(0.001, duration)));
    }
    function secondsFor(x) {
        return Math.max(0, Math.min(duration, (x - trackLeft) / trackWidth * duration));
    }

    implicitHeight: 44

    Rectangle { // Track
        id: track
        x: root.trackLeft
        width: root.trackWidth
        anchors.verticalCenter: parent.verticalCenter
        height: 8
        radius: height / 2
        color: Appearance.colors.colSecondaryContainer

        Rectangle { // Played
            width: Math.max(0, root.xFor(root.position) - root.trackLeft)
            height: parent.height
            radius: parent.radius
            color: Appearance.colors.colPrimary
        }
    }

    Rectangle { // Dim before trim start
        x: root.trackLeft
        width: root.xFor(root.trimStart) - root.trackLeft
        anchors.verticalCenter: parent.verticalCenter
        height: 24
        radius: Appearance.rounding.unsharpen
        color: ColorUtils.transparentize(Appearance.colors.colLayer0Base, 0.35)
        visible: width > 0
    }
    Rectangle { // Dim after trim end
        x: root.xFor(root.trimEnd)
        width: root.trackLeft + root.trackWidth - x
        anchors.verticalCenter: parent.verticalCenter
        height: 24
        radius: Appearance.rounding.unsharpen
        color: ColorUtils.transparentize(Appearance.colors.colLayer0Base, 0.35)
        visible: width > 0
    }
    Rectangle { // Trim range outline
        x: root.xFor(root.trimStart)
        width: root.xFor(root.trimEnd) - x
        anchors.verticalCenter: parent.verticalCenter
        height: 24
        radius: Appearance.rounding.unsharpen
        color: "transparent"
        border.width: 2
        border.color: Appearance.colors.colTertiary
        visible: root.trimmed
    }

    MouseArea { // Seeking
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        onPressed: event => root.seekRequested(root.secondsFor(event.x))
        onPositionChanged: event => {
            if (pressed) root.seekRequested(root.secondsFor(event.x));
        }
    }

    Rectangle { // Playhead
        x: root.xFor(root.position) - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: 4
        height: 30
        radius: 2
        color: Appearance.colors.colPrimary
    }

    TrimHandle {
        x: root.xFor(root.trimStart) - width
        isStart: true
        onMoved: seconds => root.trimStartRequested(Math.min(seconds, root.trimEnd - 0.5))
    }
    TrimHandle {
        x: root.xFor(root.trimEnd)
        isStart: false
        onMoved: seconds => root.trimEndRequested(Math.max(seconds, root.trimStart + 0.5))
    }

    component TrimHandle: Rectangle {
        id: handle
        property bool isStart
        signal moved(real seconds)

        anchors.verticalCenter: parent.verticalCenter
        width: root.handleWidth
        height: 32
        topLeftRadius: isStart ? Appearance.rounding.verysmall : 2
        bottomLeftRadius: topLeftRadius
        topRightRadius: isStart ? 2 : Appearance.rounding.verysmall
        bottomRightRadius: topRightRadius
        color: handleArea.pressed ? Appearance.colors.colTertiaryActive
            : handleArea.containsMouse ? Appearance.colors.colTertiaryHover : Appearance.colors.colTertiary

        Rectangle { // Grip
            anchors.centerIn: parent
            width: 2
            height: 12
            radius: 1
            color: Appearance.colors.colOnTertiary
        }

        MouseArea {
            id: handleArea
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            preventStealing: true
            cursorShape: Qt.SizeHorCursor
            onPressed: {
                root.trimDragStarted();
                handle.moved(handle.isStart ? root.trimStart : root.trimEnd);
            }
            onReleased: root.trimDragFinished()
            onCanceled: root.trimDragFinished()
            onPositionChanged: event => {
                if (!pressed) return;
                const p = mapToItem(root, event.x, event.y);
                handle.moved(root.secondsFor(p.x));
            }
        }

        StyledToolTip {
            extraVisibleCondition: false
            alternativeVisibleCondition: handleArea.containsMouse || handleArea.pressed
            text: handle.isStart ? Translation.tr("Trim start") : Translation.tr("Trim end")
        }
    }
}
