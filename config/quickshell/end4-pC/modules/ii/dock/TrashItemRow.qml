import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

RippleButton {
    id: root
    required property var item
    readonly property bool showActions: root.hovered || restoreButton.hovered || deleteButton.hovered
    readonly property bool isImage: /\.(png|jpe?g|webp|gif|bmp|svg|avif|tiff?)$/i.test(root.item.name)

    signal restoreRequested()
    signal deleteRequested()
    signal menuRequested(real x, real y)

    implicitHeight: 54
    buttonRadius: Appearance.rounding.normal
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active

    onClicked: Quickshell.execDetached(["xdg-open", root.item.path])
    altAction: event => root.menuRequested(event.x, event.y)

    contentItem: RowLayout {
        anchors {
            fill: parent
            leftMargin: 10
            rightMargin: 8
        }
        spacing: 12

        Item {
            implicitWidth: 34
            implicitHeight: 34

            IconImage {
                anchors.centerIn: parent
                visible: thumbnail.status !== Image.Ready
                implicitSize: 32
                source: SystemAppearance.iconPath(root.item.icons.find(name => AppSearch.iconExists(name)) ?? "text-x-generic", "text-x-generic")
            }

            StyledImage {
                id: thumbnail
                anchors.fill: parent
                source: root.isImage ? "file://" + root.item.path.split("/").map(part => encodeURIComponent(part)).join("/") : ""
                sourceSize: Qt.size(68, 68)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: thumbnail.width
                        height: thumbnail.height
                        radius: Appearance.rounding.unsharpenmore
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            StyledText {
                Layout.fillWidth: true
                text: root.item.name
                elide: Text.ElideMiddle
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer2
            }

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideLeft
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: {
                    const size = root.item.isDir
                        ? (root.item.childCount === 1 ? Translation.tr("1 item") : Translation.tr("%1 items").arg(root.item.childCount))
                        : Trash.formatSize(root.item.size);
                    return [Trash.prettyPath(root.item.origDir), Trash.friendlyDate(root.item.deletionDate), size]
                        .filter(part => part !== "").join(" · ");
                }
            }
        }

        RowLayout {
            spacing: 2
            opacity: root.showActions ? 1 : 0
            visible: opacity > 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            RowActionButton {
                id: restoreButton
                iconName: "restore_from_trash"
                tooltipText: Translation.tr("Put back")
                onClicked: root.restoreRequested()
            }

            RowActionButton {
                id: deleteButton
                iconName: "delete_forever"
                tooltipText: Translation.tr("Delete permanently")
                iconColor: Appearance.colors.colError
                onClicked: root.deleteRequested()
            }
        }
    }

    component RowActionButton: RippleButton {
        id: actionButton
        property string iconName
        property string tooltipText
        property color iconColor: Appearance.colors.colOnLayer2
        implicitWidth: 34
        implicitHeight: 34
        buttonRadius: Appearance.rounding.full
        colBackgroundHover: Appearance.colors.colLayer3Hover
        colRipple: Appearance.colors.colLayer3Active

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: actionButton.iconName
            iconSize: Appearance.font.pixelSize.larger
            color: actionButton.iconColor
        }

        StyledToolTip {
            text: actionButton.tooltipText
        }
    }
}
