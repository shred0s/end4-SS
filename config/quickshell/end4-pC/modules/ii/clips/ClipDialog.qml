import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/*
 * WindowDialog that stays out of the way (no input capture) while closed.
 */
WindowDialog {
    id: root

    function open() {
        root.show = true;
        root.forceActiveFocus();
    }
    function close() {
        root.show = false;
    }

    visible: root.show || hideTimer.running
    onShowChanged: {
        if (!root.show) hideTimer.restart();
    }
    onDismiss: root.close()

    Timer {
        id: hideTimer
        interval: Appearance.animation.elementMoveFast.duration
    }
}
