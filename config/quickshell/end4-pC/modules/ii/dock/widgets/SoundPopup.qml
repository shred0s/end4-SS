import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.volumeMixer
import QtQuick
import QtQuick.Layouts
import Quickshell

// Output (or input) volume, apps and devices
ColumnLayout {
    id: root
    property bool isSink: true
    readonly property var node: root.isSink ? Audio.sink : Audio.source
    readonly property bool muted: root.node?.audio?.muted ?? false
    spacing: 10

    PopupHeader {
        Layout.preferredWidth: 380
        icon: root.isSink ? (root.muted ? "volume_off" : "volume_up") : (root.muted ? "mic_off" : "mic")
        title: root.isSink ? Translation.tr("Sound") : Translation.tr("Microphone")
        subtitle: root.node ? Audio.friendlyDeviceName(root.node) : Translation.tr("No device")
    }

    PopupSlider {
        Layout.fillWidth: true
        icon: root.isSink ? (root.muted ? "volume_off" : "volume_up") : (root.muted ? "mic_off" : "mic")
        iconToggled: root.muted
        value: root.node?.audio?.volume ?? 0
        onMoved: value => {
            if (root.node?.audio) root.node.audio.volume = value;
        }
        onIconClicked: root.isSink ? Audio.toggleMute() : Audio.toggleMicMute()
    }

    // Apps and devices, as in the sidebar's volume dialog
    VolumeDialogContent {
        Layout.fillWidth: true
        Layout.preferredHeight: 240
        isSink: root.isSink
    }

    DialogButton {
        Layout.alignment: Qt.AlignRight
        buttonText: Translation.tr("Mixer")
        onClicked: Quickshell.execDetached(["bash", "-c", Config.options.apps.volumeMixer])
    }
}
