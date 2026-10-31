pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtMultimedia
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root

    required property var clipData
    property list<var> playlist: [] // Clips that prev/next walk through
    property bool theater: false

    readonly property int playlistIndex: playlist.findIndex(c => c.id === root.clipData?.id)
    readonly property var gameClips: ClipLibrary.clips.filter(c => c.game === root.clipData?.game && c.id !== root.clipData?.id).slice(0, 30)
    readonly property real duration: player.duration > 0 ? player.duration / 1000 : (root.clipData?.duration ?? 0)
    readonly property real position: player.position / 1000
    property real trimStart: 0
    property real trimEnd: duration
    property bool loop: true
    property bool wantsPlayback: false // What the user asked for; the backend's own state flips around during seeks
    property bool autoPlayPending: true // Start a newly opened clip once it has loaded
    property bool scrubbing: false // A trim handle is being dragged
    property bool resumeAfterScrub: false
    property bool precise: false
    property bool trimming: false
    property string toast: ""
    readonly property bool compact: width < 900
    // The library hands us fresh objects whenever it re-indexes; only another clip should reload the video
    readonly property string currentId: root.clipData?.id ?? ""
    readonly property string localPath: root.clipData?.local ? root.clipData.path : "" // Empty until a cloud clip is downloaded
    readonly property bool available: root.localPath.length > 0
    property string loadedPath: "" // Set by hand so an edit saved in place can reload the same path
    readonly property var transfer: ClipLibrary.transferFor(root.currentId)
    readonly property bool downloading: !!root.transfer || ClipLibrary.downloadRequests.includes(root.currentId)
    readonly property bool trimmed: root.trimStart > 0.05 || root.trimEnd < root.duration - 0.05
    // Keep controls under the picture instead of stretching across a wide window
    readonly property real controlsWidth: Math.max(640, videoOutput.contentRect.width)

    signal back()
    signal openClip(var clip)
    signal deleteRequested(var clip)
    signal renameRequested(var clip)
    signal moveRequested(var clip)

    function resetTrim() {
        root.trimStart = 0;
        root.trimEnd = root.duration;
    }
    function seek(seconds) {
        player.position = Math.max(0, Math.min(root.duration, seconds)) * 1000;
    }
    function play() {
        root.wantsPlayback = true;
        if (root.position >= root.trimEnd - 0.05 || root.position < root.trimStart) root.seek(root.trimStart);
        player.play();
    }
    function pause() {
        root.wantsPlayback = false;
        player.pause();
    }
    function togglePlay() {
        if (player.playbackState === MediaPlayer.PlayingState) root.pause();
        else root.play();
    }
    // Trim handles: hold the video still while dragging, then carry on only if it was playing
    function beginScrub() {
        root.resumeAfterScrub = player.playbackState === MediaPlayer.PlayingState;
        root.scrubbing = true;
        root.pause();
    }
    function endScrub() {
        root.scrubbing = false;
        if (root.resumeAfterScrub) root.play();
    }
    function step(frames) {
        root.pause();
        root.seek(root.position + frames / Math.max(1, root.clipData?.fps || 60));
    }
    function openSibling(offset) {
        const next = root.playlist[root.playlistIndex + offset];
        if (next) root.openClip(next);
    }
    function showToast(text) {
        root.toast = text;
        toastTimer.restart();
    }
    // replace: overwrite this clip with the trimmed part (the original goes to the trash) instead of adding a new one
    function saveTrim(replace) {
        root.trimming = true;
        if (replace) root.pause();
        ClipLibrary.trim(root.currentId, root.trimStart, root.trimEnd, root.precise, replace, ok => {
            root.trimming = false;
            if (!ok) return;
            if (replace) {
                root.reload();
                root.showToast(Translation.tr("Saved"));
            } else {
                root.showToast(Translation.tr("Saved as a new clip"));
            }
        });
    }
    function reload() {
        root.autoPlayPending = true;
        root.trimStart = 0;
        root.trimEnd = 0; // Snaps to the new length once it loads
        root.loadedPath = "";
        root.loadedPath = root.localPath;
    }

    onCurrentIdChanged: {
        root.autoPlayPending = true;
        root.trimStart = 0;
        root.trimEnd = root.clipData?.duration ?? 0;
        root.loadedPath = root.localPath;
    }
    onLocalPathChanged: { // Finished downloading while open
        if (root.loadedPath !== root.localPath) root.loadedPath = root.localPath;
    }
    Component.onCompleted: root.loadedPath = root.localPath
    onDurationChanged: {
        if (root.trimEnd <= 0 || root.trimEnd > root.duration) root.trimEnd = root.duration;
    }

    focus: true
    Keys.onPressed: event => {
        const shift = event.modifiers & Qt.ShiftModifier;
        switch (event.key) {
        case Qt.Key_Space:
        case Qt.Key_K:
            root.togglePlay(); break;
        case Qt.Key_Left:
            if (shift) root.seek(root.position - 5);
            else root.openSibling(-1);
            break;
        case Qt.Key_Right:
            if (shift) root.seek(root.position + 5);
            else root.openSibling(1);
            break;
        case Qt.Key_J:
            root.seek(root.position - 10); break;
        case Qt.Key_L:
            root.seek(root.position + 10); break;
        case Qt.Key_Comma:
            root.step(-1); break;
        case Qt.Key_Period:
            root.step(1); break;
        case Qt.Key_I:
            root.trimStart = Math.min(root.position, root.trimEnd - 0.5); break;
        case Qt.Key_O:
            root.trimEnd = Math.max(root.position, root.trimStart + 0.5); break;
        case Qt.Key_M:
            audioOutput.muted = !audioOutput.muted; break;
        case Qt.Key_T:
        case Qt.Key_F:
            root.theater = !root.theater; break;
        case Qt.Key_Up:
            audioOutput.volume = Math.min(1, audioOutput.volume + 0.05); break;
        case Qt.Key_Down:
            audioOutput.volume = Math.max(0, audioOutput.volume - 0.05); break;
        case Qt.Key_PageUp:
            root.openSibling(-1); break;
        case Qt.Key_PageDown:
            root.openSibling(1); break;
        case Qt.Key_Delete:
            root.deleteRequested(root.clipData); break;
        case Qt.Key_F2:
            root.renameRequested(root.clipData); break;
        case Qt.Key_Escape:
            if (root.theater) root.theater = false;
            else root.back();
            break;
        default:
            if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier) && root.available) {
                ClipLibrary.copyFile(root.localPath);
                root.showToast(Translation.tr("Copied clip to clipboard"));
                break;
            }
            return;
        }
        event.accepted = true;
    }

    MediaPlayer {
        id: player
        source: root.loadedPath ? `file://${root.loadedPath}` : ""
        videoOutput: videoOutput
        audioOutput: AudioOutput {
            id: audioOutput
            volume: Persistent.states.clips.volume
            onVolumeChanged: Persistent.states.clips.volume = volume
        }
        onErrorOccurred: (error, errorString) => console.warn("[ClipPlayer]", errorString)
        onPositionChanged: {
            if (player.playbackState !== MediaPlayer.PlayingState || root.trimEnd <= 0) return;
            if (root.position >= root.trimEnd || (root.position < root.trimStart - 0.25)) {
                if (root.loop) root.seek(root.trimStart);
                else {
                    root.pause();
                    root.seek(root.trimEnd);
                }
            }
        }
        onMediaStatusChanged: {
            // play() is ignored while loading, so a new clip starts here. Paused seeks also report
            // LoadedMedia, which is why this only happens once per clip.
            if (mediaStatus === MediaPlayer.LoadedMedia && root.autoPlayPending) {
                root.autoPlayPending = false;
                if (root.trimEnd <= 0) root.trimEnd = root.duration; // Reloaded after an edit
                root.play();
            }
            if (mediaStatus === MediaPlayer.EndOfMedia && root.loop && root.wantsPlayback && !root.scrubbing) {
                root.seek(root.trimStart);
                player.play();
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 16

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            // Header
            RowLayout {
                Layout.fillWidth: true
                visible: !root.theater
                spacing: 6

                IconButton {
                    symbol: "arrow_back"
                    tooltip: Translation.tr("Back to library (Esc)")
                    onClicked: root.back()
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: root.clipData?.name ?? ""
                        elide: Text.ElideRight
                        color: Appearance.colors.colOnLayer1
                        font {
                            family: Appearance.font.family.title
                            pixelSize: Appearance.font.pixelSize.title
                            variableAxes: Appearance.font.variableAxes.title
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: `${root.clipData?.game ?? ""}  ·  ${Qt.formatDateTime(new Date((root.clipData?.created ?? 0) * 1000), "ddd d MMM yyyy, HH:mm")}`
                        elide: Text.ElideRight
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
                IconButton {
                    symbol: "star"
                    filled: root.clipData?.favorite ?? false
                    activeColor: "#ffd54f"
                    tooltip: filled ? Translation.tr("Remove from favorites") : Translation.tr("Add to favorites")
                    onClicked: ClipLibrary.toggleFavorite(root.currentId)
                }
                IconButton {
                    symbol: "cloud_upload"
                    visible: ClipLibrary.cloudConnected && root.available && !(root.clipData?.cloud ?? false)
                    tooltip: Translation.tr("Upload to the cloud")
                    onClicked: {
                        ClipLibrary.upload([root.currentId]);
                        root.showToast(Translation.tr("Uploading to the cloud"));
                    }
                }
                IconButton {
                    symbol: "content_copy"
                    visible: root.available
                    tooltip: Translation.tr("Copy clip to clipboard (Ctrl+C)")
                    onClicked: {
                        ClipLibrary.copyFile(root.localPath);
                        root.showToast(Translation.tr("Copied clip to clipboard"));
                    }
                }
                IconButton {
                    symbol: "edit"
                    tooltip: Translation.tr("Rename (F2)")
                    onClicked: root.renameRequested(root.clipData)
                }
                IconButton {
                    symbol: "drive_file_move"
                    visible: !root.compact
                    tooltip: Translation.tr("Change game")
                    onClicked: root.moveRequested(root.clipData)
                }
                IconButton {
                    symbol: "folder_open"
                    visible: !root.compact && root.available
                    tooltip: Translation.tr("Show in folder")
                    onClicked: ClipLibrary.showInFolder(root.localPath)
                }
                IconButton {
                    symbol: "open_in_new"
                    visible: !root.compact && root.available
                    tooltip: Translation.tr("Open in external player")
                    onClicked: {
                        root.pause();
                        ClipLibrary.openExternally(root.localPath);
                    }
                }
                IconButton {
                    symbol: "delete"
                    tooltip: Translation.tr("Delete (Del)")
                    onClicked: root.deleteRequested(root.clipData)
                }
            }

            // Video
            Rectangle {
                id: videoContainer
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Appearance.rounding.normal
                color: "#000000"

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: videoContainer.width
                        height: videoContainer.height
                        radius: videoContainer.radius
                    }
                }

                VideoOutput {
                    id: videoOutput
                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectFit
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.available
                    onClicked: {
                        root.forceActiveFocus();
                        root.togglePlay();
                    }
                    onDoubleClicked: root.theater = !root.theater
                }

                HoverHandler {
                    id: videoHover
                }
                ClipNavButton {
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: 12
                    }
                    symbol: "chevron_left"
                    tooltip: Translation.tr("Previous clip (←)")
                    shown: videoHover.hovered && root.playlistIndex > 0
                    onClicked: root.openSibling(-1)
                }
                ClipNavButton {
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        rightMargin: 12
                    }
                    symbol: "chevron_right"
                    tooltip: Translation.tr("Next clip (→)")
                    shown: videoHover.hovered && root.playlistIndex >= 0 && root.playlistIndex < root.playlist.length - 1
                    onClicked: root.openSibling(1)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: root.available && player.playbackState !== MediaPlayer.PlayingState && !root.scrubbing
                    text: "play_circle"
                    fill: 1
                    iconSize: 84
                    color: "#ffffff"
                    opacity: 0.85
                }

                // Only in the cloud so far
                Item {
                    anchors.fill: parent
                    visible: !root.available

                    Image {
                        anchors.fill: parent
                        source: root.clipData?.thumb ? `file://${root.clipData.thumb}` : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        opacity: 0.35
                    }
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 48, 360)
                        spacing: 12

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: "cloud"
                            fill: 1
                            iconSize: 56
                            color: "#ffffff"
                        }
                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            text: root.downloading
                                ? Translation.tr("Downloading… %1%").arg(Math.round((root.transfer?.progress ?? 0) * 100))
                                : ClipLibrary.cloudConnected
                                    ? Translation.tr("This clip is in the cloud. Download it (%1) to watch and edit it here.").arg(ClipLibrary.formatSize(root.clipData?.size ?? 0))
                                    : Translation.tr("This clip is in the cloud. Connect to R2 in the settings to download it.")
                            color: "#ffffff"
                            font.pixelSize: Appearance.font.pixelSize.normal
                        }
                        StyledProgressBar {
                            Layout.fillWidth: true
                            visible: root.downloading
                            value: root.transfer?.progress ?? 0
                        }
                        RippleButton {
                            Layout.alignment: Qt.AlignHCenter
                            visible: !root.downloading && ClipLibrary.cloudConnected
                            implicitHeight: 40
                            implicitWidth: downloadRow.implicitWidth + 32
                            buttonRadius: height / 2
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            colRipple: Appearance.colors.colPrimaryActive
                            onClicked: ClipLibrary.download([root.currentId])
                            contentItem: RowLayout {
                                id: downloadRow
                                anchors.centerIn: parent
                                spacing: 6
                                MaterialSymbol {
                                    text: "download"
                                    iconSize: 20
                                    color: Appearance.colors.colOnPrimary
                                }
                                StyledText {
                                    text: Translation.tr("Download")
                                    color: Appearance.colors.colOnPrimary
                                }
                            }
                        }
                    }
                }

                Rectangle { // Toast
                    anchors {
                        horizontalCenter: parent.horizontalCenter
                        top: parent.top
                        topMargin: 16
                    }
                    opacity: toastTimer.running ? 1 : 0
                    visible: opacity > 0
                    implicitWidth: toastText.implicitWidth + 28
                    implicitHeight: toastText.implicitHeight + 14
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colTooltip
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    StyledText {
                        id: toastText
                        anchors.centerIn: parent
                        text: root.toast
                        color: Appearance.colors.colOnTooltip
                    }
                    Timer {
                        id: toastTimer
                        interval: 2500
                    }
                }
            }

            ClipTimeline {
                enabled: root.available
                Layout.fillWidth: true
                Layout.maximumWidth: root.controlsWidth
                Layout.alignment: Qt.AlignHCenter
                duration: root.duration
                position: root.position
                trimStart: root.trimStart
                trimEnd: root.trimEnd
                onSeekRequested: seconds => root.seek(seconds)
                onTrimDragStarted: root.beginScrub()
                onTrimDragFinished: root.endScrub()
                onTrimStartRequested: seconds => {
                    root.trimStart = seconds;
                    root.seek(seconds);
                }
                onTrimEndRequested: seconds => {
                    root.trimEnd = seconds;
                    root.seek(seconds);
                }
            }

            // Playback controls
            RowLayout {
                Layout.fillWidth: true
                Layout.maximumWidth: root.controlsWidth
                Layout.alignment: Qt.AlignHCenter
                spacing: 4

                IconButton {
                    symbol: "skip_previous"
                    enabled: root.playlistIndex > 0
                    tooltip: Translation.tr("Previous clip (←)")
                    onClicked: root.openSibling(-1)
                }
                RippleButton {
                    implicitWidth: 52
                    implicitHeight: 40
                    enabled: root.available
                    opacity: enabled ? 1 : 0.4
                    buttonRadius: height / 2
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    onClicked: root.togglePlay()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: player.playbackState === MediaPlayer.PlayingState ? "pause" : "play_arrow"
                        fill: 1
                        iconSize: 26
                        color: Appearance.colors.colOnPrimary
                    }
                }
                IconButton {
                    symbol: "skip_next"
                    enabled: root.playlistIndex >= 0 && root.playlistIndex < root.playlist.length - 1
                    tooltip: Translation.tr("Next clip (→)")
                    onClicked: root.openSibling(1)
                }
                StyledText {
                    Layout.leftMargin: 8
                    text: `${ClipLibrary.formatDuration(root.position)} / ${ClipLibrary.formatDuration(root.duration)}`
                    color: Appearance.colors.colOnLayer1
                    font.family: Appearance.font.family.numbers
                }
                Item { Layout.fillWidth: true }

                IconButton {
                    symbol: "repeat"
                    filled: root.loop
                    toggled: root.loop
                    tooltip: Translation.tr("Loop")
                    onClicked: root.loop = !root.loop
                }
                RippleButton {
                    implicitHeight: 40
                    implicitWidth: speedText.implicitWidth + 24
                    buttonRadius: height / 2
                    onClicked: {
                        const rates = [0.25, 0.5, 1, 1.5, 2];
                        player.playbackRate = rates[(rates.indexOf(player.playbackRate) + 1) % rates.length];
                    }
                    contentItem: StyledText {
                        id: speedText
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: `${player.playbackRate}×`
                        color: Appearance.colors.colOnLayer1
                        font.family: Appearance.font.family.numbers
                    }
                    StyledToolTip {
                        text: Translation.tr("Playback speed")
                    }
                }
                IconButton {
                    symbol: audioOutput.muted || audioOutput.volume === 0 ? "volume_off" : audioOutput.volume < 0.5 ? "volume_down" : "volume_up"
                    tooltip: Translation.tr("Mute (M)")
                    onClicked: audioOutput.muted = !audioOutput.muted
                }
                StyledSlider {
                    Layout.fillWidth: false
                    Layout.preferredWidth: 110
                    Layout.maximumWidth: 110
                    focusPolicy: Qt.NoFocus
                    configuration: StyledSlider.Configuration.XS
                    from: 0
                    to: 1
                    value: audioOutput.volume
                    onMoved: {
                        audioOutput.volume = value;
                        audioOutput.muted = false;
                    }
                }
                IconButton {
                    symbol: root.theater ? "close_fullscreen" : "open_in_full"
                    tooltip: Translation.tr("Theater mode (T)")
                    onClicked: root.theater = !root.theater
                }
            }

            // Trim controls
            Rectangle {
                Layout.fillWidth: true
                Layout.maximumWidth: root.controlsWidth
                Layout.alignment: Qt.AlignHCenter
                visible: !root.theater && root.available
                implicitHeight: trimRow.implicitHeight + 16
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2

                GridLayout {
                    id: trimRow
                    anchors {
                        fill: parent
                        margins: 8
                        leftMargin: 14
                    }
                    columns: root.compact || width < trimInfoRow.implicitWidth + trimActionsRow.implicitWidth + columnSpacing ? 1 : 2
                    rowSpacing: 6
                    columnSpacing: 6

                    RowLayout {
                        id: trimInfoRow
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialSymbol {
                            text: "content_cut"
                            iconSize: 20
                            color: Appearance.colors.colTertiary
                        }
                        StyledText {
                            text: Translation.tr("Trim")
                            color: Appearance.colors.colOnLayer2
                            font.weight: Font.Medium
                        }
                        StyledText {
                            Layout.leftMargin: 6
                            text: `${ClipLibrary.formatDuration(root.trimStart)} – ${ClipLibrary.formatDuration(root.trimEnd)}  (${(root.trimEnd - root.trimStart).toFixed(1)}s)`
                            color: Appearance.colors.colSubtext
                            font.family: Appearance.font.family.numbers
                        }
                        Item { Layout.fillWidth: true }
                        PillButton {
                            label: Translation.tr("Start here (I)")
                            onClicked: root.trimStart = Math.min(root.position, root.trimEnd - 0.5)
                        }
                        PillButton {
                            label: Translation.tr("End here (O)")
                            onClicked: root.trimEnd = Math.max(root.position, root.trimStart + 0.5)
                        }
                        PillButton {
                            label: Translation.tr("Reset")
                            enabled: root.trimmed
                            onClicked: root.resetTrim()
                        }
                    }

                    RowLayout {
                        id: trimActionsRow
                        Layout.alignment: Qt.AlignRight
                        spacing: 6

                        RowLayout {
                            spacing: 2
                            HoverHandler {
                                id: preciseHover
                            }
                            StyledSwitch {
                                focusPolicy: Qt.NoFocus
                                checked: root.precise
                                onToggled: root.precise = checked
                            }
                            StyledText {
                                text: Translation.tr("Precise")
                                color: Appearance.colors.colOnLayer2
                            }
                            StyledToolTip {
                                extraVisibleCondition: false
                                alternativeVisibleCondition: preciseHover.hovered
                                text: Translation.tr("Re-encode for frame-accurate cuts (slower). Off: instant cut at the nearest keyframe.")
                            }
                        }
                        RippleButton {
                            implicitHeight: 36
                            implicitWidth: saveCopyRow.implicitWidth + 28
                            buttonRadius: height / 2
                            enabled: !root.trimming && root.trimmed
                            opacity: enabled ? 1 : 0.5
                            colBackground: Appearance.colors.colLayer3
                            colBackgroundHover: Appearance.colors.colLayer3Hover
                            colRipple: Appearance.colors.colLayer3Active
                            onClicked: root.saveTrim(false)
                            contentItem: RowLayout {
                                id: saveCopyRow
                                anchors.centerIn: parent
                                spacing: 6
                                MaterialSymbol {
                                    text: "library_add"
                                    iconSize: 18
                                    color: Appearance.colors.colOnLayer3
                                }
                                StyledText {
                                    text: Translation.tr("Save as new clip")
                                    color: Appearance.colors.colOnLayer3
                                }
                            }
                            StyledToolTip {
                                text: Translation.tr("Keep this clip as it is and add the trimmed part as a new clip")
                            }
                        }
                        RippleButton {
                            implicitHeight: 36
                            implicitWidth: saveRow.implicitWidth + 28
                            buttonRadius: height / 2
                            enabled: !root.trimming && root.trimmed
                            opacity: enabled ? 1 : 0.5
                            colBackground: Appearance.colors.colTertiaryContainer
                            colBackgroundHover: Appearance.colors.colTertiaryContainerHover
                            colRipple: Appearance.colors.colTertiaryContainerActive
                            onClicked: root.saveTrim(true)
                            contentItem: RowLayout {
                                id: saveRow
                                anchors.centerIn: parent
                                spacing: 6
                                MaterialSymbol {
                                    text: root.trimming ? "hourglass_empty" : "save"
                                    iconSize: 18
                                    color: Appearance.colors.colOnTertiaryContainer
                                }
                                StyledText {
                                    text: root.trimming ? Translation.tr("Saving…") : Translation.tr("Save")
                                    color: Appearance.colors.colOnTertiaryContainer
                                }
                            }
                            StyledToolTip {
                                text: Translation.tr("Replace this clip with the trimmed part. The original goes to the trash.")
                            }
                        }
                    }
                }
            }
        }

        // Details + more from this game
        ColumnLayout {
            Layout.preferredWidth: 300
            Layout.maximumWidth: 300
            Layout.fillHeight: true
            visible: !root.theater && !root.compact
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: detailsColumn.implicitHeight + 28
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2

                ColumnLayout {
                    id: detailsColumn
                    anchors {
                        fill: parent
                        margins: 14
                    }
                    spacing: 8

                    StyledText {
                        text: Translation.tr("Details")
                        color: Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Medium
                    }
                    DetailRow { icon: "sports_esports"; label: Translation.tr("Game"); value: root.clipData?.game ?? "" }
                    DetailRow { icon: "schedule"; label: Translation.tr("Length"); value: ClipLibrary.formatDuration(root.duration) }
                    DetailRow {
                        icon: "aspect_ratio"
                        label: Translation.tr("Resolution")
                        value: root.clipData?.width ? `${root.clipData.width}×${root.clipData.height}` : "–"
                    }
                    DetailRow { icon: "speed"; label: Translation.tr("Frame rate"); value: root.clipData?.fps ? `${root.clipData.fps} fps` : "–" }
                    DetailRow { icon: "hard_drive"; label: Translation.tr("Size"); value: ClipLibrary.formatSize(root.clipData?.size ?? 0) }
                    DetailRow {
                        icon: "cloud"
                        label: Translation.tr("Cloud")
                        visible: ClipLibrary.cloudConnected || !root.available
                        value: root.transfer ? Translation.tr("Transferring %1%").arg(Math.round((root.transfer.progress ?? 0) * 100))
                            : !root.available ? Translation.tr("Only in the cloud")
                            : root.clipData?.synced ? Translation.tr("Synced")
                            : root.clipData?.cloud ? Translation.tr("Waiting to sync")
                            : Translation.tr("Not uploaded")
                    }
                    DetailRow { icon: "description"; label: Translation.tr("File"); value: root.clipData?.file ?? "" }
                }
            }

            StyledText {
                Layout.topMargin: 6
                Layout.leftMargin: 4
                visible: root.gameClips.length > 0
                text: Translation.tr("More from %1").arg(root.clipData?.game ?? "")
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.Medium
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            StyledListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 4
                model: root.gameClips
                delegate: RippleButton {
                    id: upNext
                    required property var modelData
                    width: ListView.view.width
                    implicitHeight: 64
                    buttonRadius: Appearance.rounding.small
                    onClicked: root.openClip(upNext.modelData)
                    contentItem: RowLayout {
                        anchors {
                            fill: parent
                            margins: 4
                        }
                        spacing: 10
                        Rectangle {
                            id: upNextThumb
                            Layout.preferredWidth: 100
                            Layout.fillHeight: true
                            radius: Appearance.rounding.verysmall
                            color: Appearance.colors.colLayer3
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: upNextThumb.width
                                    height: upNextThumb.height
                                    radius: upNextThumb.radius
                                }
                            }
                            Image {
                                anchors.fill: parent
                                source: upNext.modelData.thumb ? `file://${upNext.modelData.thumb}` : ""
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: 200
                                asynchronous: true
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText {
                                Layout.fillWidth: true
                                text: upNext.modelData.name
                                elide: Text.ElideRight
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: `${ClipLibrary.formatDuration(upNext.modelData.duration ?? 0)}  ·  ${ClipLibrary.formatRelative(upNext.modelData.created)}`
                                elide: Text.ElideRight
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }
                    }
                }
            }
        }
    }

    component IconButton: RippleButton {
        id: iconButton
        focusPolicy: Qt.NoFocus
        property string symbol
        property string tooltip
        property bool filled: false
        property color activeColor: Appearance.colors.colOnPrimary
        implicitWidth: 40
        implicitHeight: 40
        buttonRadius: height / 2
        opacity: enabled ? 1 : 0.4
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: iconButton.symbol
            iconSize: 22
            fill: iconButton.filled ? 1 : 0
            color: iconButton.toggled ? Appearance.colors.colOnPrimary
                : iconButton.filled ? iconButton.activeColor : Appearance.colors.colOnLayer1
        }
        StyledToolTip {
            text: iconButton.tooltip
        }
    }

    component PillButton: RippleButton {
        id: pillButton
        focusPolicy: Qt.NoFocus
        property alias label: pillText.text
        implicitHeight: 36
        implicitWidth: pillText.implicitWidth + 24
        buttonRadius: height / 2
        opacity: enabled ? 1 : 0.5
        colBackground: Appearance.colors.colLayer3
        colBackgroundHover: Appearance.colors.colLayer3Hover
        colRipple: Appearance.colors.colLayer3Active
        contentItem: StyledText {
            id: pillText
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            color: Appearance.colors.colOnLayer3
        }
    }

    component DetailRow: RowLayout {
        property string icon
        property string label
        property string value
        Layout.fillWidth: true
        spacing: 10
        MaterialSymbol {
            text: parent.icon
            iconSize: 18
            color: Appearance.colors.colSubtext
        }
        StyledText {
            text: parent.label
            color: Appearance.colors.colSubtext
        }
        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            text: parent.value
            elide: Text.ElideMiddle
            color: Appearance.colors.colOnLayer2
        }
    }
}
