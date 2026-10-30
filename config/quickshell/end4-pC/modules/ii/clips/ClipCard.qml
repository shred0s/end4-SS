pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtMultimedia
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root

    required property var clipData
    property bool selected: false
    property bool selectionMode: false
    property bool showGame: true
    readonly property bool favorite: root.clipData.favorite
    readonly property bool hovered: mouseArea.containsMouse || favoriteButton.hovered || checkButton.hovered
    readonly property var transfer: ClipLibrary.transferFor(root.clipData.id)
    readonly property bool downloading: !!root.transfer || ClipLibrary.downloadRequests.includes(root.clipData.id)
    // Only for clips on Proton Drive (or on their way there)
    readonly property string syncSymbol: {
        if (root.transfer) return root.transfer.phase === "download" ? "cloud_download" : "cloud_upload";
        if (!root.clipData.local) return "cloud";
        if (!root.clipData.cloud) return "";
        return root.clipData.synced ? "cloud_done" : "cloud_sync";
    }

    signal play()
    signal toggleSelected()
    signal menuRequested(real x, real y)

    implicitHeight: thumbnailContainer.height + infoColumn.implicitHeight + 10

    Rectangle {
        id: thumbnailContainer
        width: parent.width
        height: Math.round(width * 9 / 16)
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: thumbnailContainer.width
                height: thumbnailContainer.height
                radius: thumbnailContainer.radius
            }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            visible: thumbnail.status !== Image.Ready
            text: "movie"
            iconSize: 40
            color: Appearance.colors.colSubtext
        }

        Item { // Hover zoom stays inside the rounded mask
            anchors.fill: parent
            scale: root.hovered && !root.selectionMode ? 1.06 : 1
            Behavior on scale {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Image {
                id: thumbnail
                anchors.fill: parent
                source: root.clipData.thumb ? `file://${root.clipData.thumb}` : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 640
                asynchronous: true
                cache: true
                opacity: root.clipData.local ? 1 : 0.6 // Not downloaded yet
            }

            // Muted preview after hovering for a moment
            Loader {
                id: previewLoader
                anchors.fill: parent
                active: false
                sourceComponent: Item {
                    MediaPlayer {
                        id: previewPlayer
                        source: `file://${root.clipData.path}`
                        videoOutput: previewOutput
                        loops: MediaPlayer.Infinite
                        onMediaStatusChanged: if (mediaStatus === MediaPlayer.LoadedMedia) previewPlayer.play()
                    }
                    VideoOutput {
                        id: previewOutput
                        anchors.fill: parent
                        fillMode: VideoOutput.PreserveAspectCrop
                    }
                }
            }
        }
        Timer {
            id: previewTimer
            interval: 600
            running: root.hovered && !root.selectionMode && root.clipData.local
            onTriggered: previewLoader.active = true
        }
        Connections {
            target: root
            function onHoveredChanged() {
                if (!root.hovered) previewLoader.active = false;
            }
        }

        Rectangle { // Bottom shade for the badges
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            height: parent.height * 0.4
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: ColorUtils.transparentize("#000000", 0.45) }
            }
        }

        Rectangle { // Selection tint
            anchors.fill: parent
            color: Appearance.colors.colPrimary
            opacity: root.selected ? 0.25 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            visible: root.hovered && !root.selectionMode && !previewLoader.active
            text: root.clipData.local ? "play_circle" : "download_for_offline"
            fill: 1
            iconSize: 52
            color: "#ffffff"
            opacity: 0.9
        }

        Row {
            anchors {
                right: parent.right
                bottom: parent.bottom
                margins: 8
            }
            spacing: 4
            Badge {
                visible: root.syncSymbol.length > 0
                symbol: root.syncSymbol
                text: root.transfer ? `${Math.round((root.transfer.progress ?? 0) * 100)}%` : ""
            }
            Badge {
                text: ClipLibrary.formatDuration(root.clipData.duration ?? 0)
            }
        }

        Rectangle { // Upload/download progress
            anchors {
                left: parent.left
                bottom: parent.bottom
            }
            visible: root.downloading || !!root.transfer
            height: 3
            width: parent.width * (root.transfer?.progress ?? 0)
            color: Appearance.colors.colPrimary
        }

        Badge {
            anchors {
                left: parent.left
                bottom: parent.bottom
                margins: 8
            }
            visible: (root.clipData.height ?? 0) > 0
            text: `${root.clipData.height}p${root.clipData.fps ? root.clipData.fps : ""}`
        }

        CardIconButton {
            id: checkButton
            anchors {
                left: parent.left
                top: parent.top
                margins: 6
            }
            visible: root.hovered || root.selectionMode
            symbol: root.selected ? "check_circle" : "radio_button_unchecked"
            filled: root.selected
            activeColor: Appearance.colors.colPrimary
            onClicked: root.toggleSelected()
        }

        CardIconButton {
            id: favoriteButton
            anchors {
                right: parent.right
                top: parent.top
                margins: 6
            }
            visible: root.favorite || root.hovered
            symbol: "star"
            filled: root.favorite
            activeColor: "#ffd54f"
            onClicked: ClipLibrary.toggleFavorite(root.clipData.id)
        }

        Rectangle { // Selected outline
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: root.selected ? 3 : 0
            border.color: Appearance.colors.colPrimary
        }
    }

    ColumnLayout {
        id: infoColumn
        anchors {
            left: parent.left
            right: parent.right
            top: thumbnailContainer.bottom
            topMargin: 8
            leftMargin: 2
            rightMargin: 2
        }
        spacing: 2

        StyledText {
            Layout.fillWidth: true
            text: root.clipData.name
            elide: Text.ElideRight
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.Medium
        }
        StyledText {
            Layout.fillWidth: true
            text: [root.showGame ? root.clipData.game : "", ClipLibrary.formatRelative(root.clipData.created), ClipLibrary.formatSize(root.clipData.size)]
                .filter(s => s.length > 0).join("  ·  ")
            elide: Text.ElideRight
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        z: -1
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: event => {
            if (event.button === Qt.RightButton) {
                root.menuRequested(event.x, event.y);
            } else if (root.selectionMode || (event.modifiers & Qt.ControlModifier)) {
                root.toggleSelected();
            } else {
                root.play();
            }
        }
    }

    component Badge: Rectangle {
        id: badge
        property alias text: badgeText.text
        property string symbol
        implicitWidth: badgeRow.implicitWidth + 12
        implicitHeight: badgeText.implicitHeight + 4
        radius: Appearance.rounding.full
        color: ColorUtils.transparentize("#000000", 0.35)
        Row {
            id: badgeRow
            anchors.centerIn: parent
            spacing: 3
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                visible: text.length > 0
                text: badge.symbol
                iconSize: Appearance.font.pixelSize.normal
                fill: 1
                color: "#ffffff"
            }
            StyledText {
                id: badgeText
                anchors.verticalCenter: parent.verticalCenter
                visible: text.length > 0
                color: "#ffffff"
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
            }
        }
    }

    component CardIconButton: RippleButton {
        id: iconButton
        property string symbol
        property bool filled: false
        property color activeColor
        implicitWidth: 32
        implicitHeight: 32
        buttonRadius: height / 2
        colBackground: ColorUtils.transparentize("#000000", 0.55)
        colBackgroundHover: ColorUtils.transparentize("#000000", 0.35)
        colRipple: ColorUtils.transparentize("#000000", 0.2)
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: iconButton.symbol
            iconSize: 20
            fill: iconButton.filled ? 1 : 0
            color: iconButton.filled ? iconButton.activeColor : "#ffffff"
        }
    }
}
