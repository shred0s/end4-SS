import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.dock
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris

// The dock's media card, kept even when nothing plays; click for the full player
DockMedia {
    id: root
    property bool inDock: false
    readonly property bool holdOpen: mediaPopup.isOpen
    readonly property bool available: true
    // Set by the widget row; the media card has its own look
    property string toneName
    property string groupPosition
    // Margins the widget row gives it across the dock
    readonly property real innerMargin: DockStyle.mediaInnerMargin
    readonly property real outerMargin: DockStyle.mediaOuterMargin

    persistent: true
    buttonPadding: DockStyle.padding
    transform: Translate { x: root.inDock && DockStyle.magnifying ? DockMagnify.shiftOf(root) : 0 }
    onClicked: mediaPopup.toggle()

    DockWidgetPopup {
        id: mediaPopup
        button: root
        content: ColumnLayout {
            spacing: 10

            Loader {
                active: MprisController.activePlayer !== null
                visible: active
                Layout.preferredWidth: 420
                Layout.preferredHeight: 170
                sourceComponent: Player {
                    player: MprisController.activePlayer
                    allowLyrics: false
                    radius: Appearance.rounding.normal
                }
            }

            // Nothing to show
            ColumnLayout {
                visible: MprisController.activePlayer === null
                Layout.preferredWidth: 300
                spacing: 6
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "music_off"
                    iconSize: 40
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Nothing is playing")
                    color: Appearance.colors.colSubtext
                }
            }

            // Pick the player when there's more than one
            Flow {
                visible: Mpris.players.values.length > 1
                Layout.preferredWidth: 420
                spacing: 6
                Repeater {
                    model: Mpris.players.values
                    delegate: RippleButton {
                        required property MprisPlayer modelData
                        readonly property bool current: modelData === MprisController.activePlayer
                        implicitHeight: 32
                        horizontalPadding: 12
                        buttonRadius: height / 2
                        colBackground: current ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                        colBackgroundHover: current ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
                        onClicked: MprisController.manualPlayer = modelData
                        contentItem: StyledText {
                            text: modelData.identity || modelData.desktopEntry || Translation.tr("Player")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                        }
                    }
                }
            }
        }
    }
}
