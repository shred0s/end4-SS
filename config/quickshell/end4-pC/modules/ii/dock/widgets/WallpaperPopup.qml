import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

// Wallpapers in the current folder; click one to use it
ColumnLayout {
    id: root
    property var onOpenPicker: () => {}
    readonly property int columns: 4
    readonly property real thumbWidth: 112
    readonly property real thumbHeight: 70
    spacing: 10
    Component.onCompleted: Wallpapers.load()

    PopupHeader {
        Layout.preferredWidth: root.columns * (root.thumbWidth + 6) - 6
        icon: "imagesmode"
        title: Translation.tr("Wallpaper")
        subtitle: Wallpapers.effectiveDirectory.split("/").pop()
    }

    StyledFlickable {
        Layout.preferredWidth: root.columns * (root.thumbWidth + 6) - 6
        Layout.preferredHeight: Math.min(3.5 * (root.thumbHeight + 6), grid.implicitHeight)
        contentHeight: grid.implicitHeight
        clip: true

        Grid {
            id: grid
            columns: root.columns
            spacing: 6

            Repeater {
                model: Wallpapers.wallpaperModel
                delegate: RippleButton {
                    id: thumb
                    required property var model
                    readonly property bool current: model.filePath === Config.options.background.wallpaperPath
                    visible: !model.fileIsDir
                    width: visible ? root.thumbWidth : 0
                    height: visible ? root.thumbHeight : 0
                    buttonRadius: Appearance.rounding.small
                    padding: 0
                    onClicked: Wallpapers.select(model.filePath)

                    contentItem: Item {
                        ThumbnailImage {
                            anchors.fill: parent
                            sourcePath: thumb.model.filePath
                            sourceSize.width: root.thumbWidth * 2
                            sourceSize.height: root.thumbHeight * 2
                            fillMode: Image.PreserveAspectCrop
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: thumb.width
                                    height: thumb.height
                                    radius: Appearance.rounding.small
                                }
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            radius: Appearance.rounding.small
                            border.width: thumb.current ? 3 : thumb.hovered ? 2 : 0
                            border.color: Appearance.colors.colPrimary
                        }
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.alignment: Qt.AlignRight
        spacing: 4
        DialogButton {
            buttonText: Translation.tr("Random")
            onClicked: Wallpapers.randomFromCurrentFolder()
        }
        DialogButton {
            buttonText: Translation.tr("More…")
            onClicked: root.onOpenPicker()
        }
    }
}
