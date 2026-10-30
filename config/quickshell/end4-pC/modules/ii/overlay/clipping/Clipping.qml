pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overlay

StyledOverlayWidget {
    id: root
    minimumWidth: 310
    minimumHeight: 130

    readonly property int clipSeconds: Config.options.clips.clipSeconds
    readonly property int bufferSeconds: Config.options.clips.bufferSeconds

    contentItem: OverlayBackground {
        id: contentItem
        radius: root.contentRadius
        property real padding: 8
        ColumnLayout {
            id: contentColumn
            anchors.centerIn: parent
            spacing: 10

            Row {
                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                spacing: 10

                BigClipButton {
                    materialSymbol: Clips.starting ? "hourglass_empty" : "power_settings_new"
                    name: Clips.running ? Translation.tr("Stop clipping") : Translation.tr("Start clipping")
                    toggled: Clips.running
                    onClicked: Clips.toggle()
                }

                BigClipButton {
                    materialSymbol: [5, 10, 30].includes(root.clipSeconds) ? `replay_${root.clipSeconds}` : "content_cut"
                    name: Translation.tr("Save last %1 seconds").arg(root.clipSeconds)
                    enabled: Clips.running && !Clips.saving
                    onClicked: {
                        GlobalStates.overlayOpen = false;
                        Clips.saveClip();
                    }
                }

                BigClipButton {
                    materialSymbol: "history"
                    name: Translation.tr("Save whole buffer (%1 seconds)").arg(root.bufferSeconds)
                    enabled: Clips.running && !Clips.saving
                    onClicked: {
                        GlobalStates.overlayOpen = false;
                        Clips.saveBuffer();
                    }
                }

                BigClipButton {
                    materialSymbol: Config.options.clips.microphone ? "mic" : "mic_off"
                    name: Config.options.clips.microphone ? Translation.tr("Microphone is recorded in clips") : Translation.tr("Microphone is not recorded in clips")
                    toggled: Config.options.clips.microphone
                    onClicked: Config.options.clips.microphone = !Config.options.clips.microphone
                }
            }

            RippleButton {
                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                Layout.fillWidth: false
                buttonRadius: height / 2
                colBackground: Appearance.colors.colLayer3
                colBackgroundHover: Appearance.colors.colLayer3Hover
                colRipple: Appearance.colors.colLayer3Active
                onClicked: {
                    GlobalStates.overlayOpen = false;
                    Clips.openViewer("");
                }
                contentItem: Row {
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "video_library"
                        iconSize: 20
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Translation.tr("View clips")
                    }
                }
            }
        }
    }

    component BigClipButton: RippleButton {
        id: bigButton
        required property string materialSymbol
        required property string name
        implicitHeight: 66
        implicitWidth: 66
        buttonRadius: height / 2
        opacity: enabled ? 1 : 0.5

        colBackground: Appearance.colors.colLayer3
        colBackgroundHover: Appearance.colors.colLayer3Hover
        colRipple: Appearance.colors.colLayer3Active

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: bigButton.materialSymbol
            iconSize: 28
            fill: bigButton.toggled ? 1 : 0
            color: bigButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
        }

        StyledToolTip {
            text: bigButton.name
        }
    }
}
