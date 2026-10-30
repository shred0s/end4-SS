import qs.services
import qs.modules.common
import QtQuick
import Quickshell

DockWidgetButton {
    id: root
    readonly property bool recording: Persistent.states.record.enable
    property int elapsed: 0

    symbol: root.recording ? "stop_circle" : "screen_record"
    symbolFill: root.recording
    active: root.recording
    tooltipText: root.recording
        ? Translation.tr("Stop recording (%1)").arg(`${Math.floor(root.elapsed / 60)}:${String(root.elapsed % 60).padStart(2, "0")}`)
        : Translation.tr("Record the screen")
    onClicked: Quickshell.execDetached([Directories.recordScriptPath])
    onRecordingChanged: root.elapsed = 0

    Timer {
        running: root.recording
        interval: 1000
        repeat: true
        onTriggered: root.elapsed++
    }
}
