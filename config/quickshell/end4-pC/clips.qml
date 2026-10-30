//@ pragma UseQApplication
//@ pragma AppId qs-clips
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
//@ pragma Env QT_LOGGING_RULES=qt.text.font.db.info=false

// The clip library as its own app. Open it with scripts/videos/clips-app.sh [clip id], which brings an
// already open window forward instead of starting a second one.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.ii.clips

ShellRoot {
    id: root

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme();
        const clipId = Quickshell.env("QS_CLIPS_OPEN");
        if (clipId) ClipLibrary.openClip(clipId);
    }

    FloatingWindow {
        title: "Clips"
        color: Appearance.colors.colUiBackground

        implicitWidth: 1280
        implicitHeight: 800
        minimumSize: Qt.size(960, 620)

        visible: true
        onVisibleChanged: {
            if (!visible) Qt.quit();
        }

        ClipViewerContent {
            anchors.fill: parent
            onCloseRequested: Qt.quit()
        }
    }

    IpcHandler {
        target: "clipviewer"

        function show(): void {}
        function open(clipId: string): void {
            ClipLibrary.openClip(clipId);
        }
        function close(): void {
            Qt.quit();
        }
    }
}
