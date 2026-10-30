import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common

/*
 * Clipping hotkeys and IPC for the shell. The library itself is the separate Clips app (clips.qml).
 */
Scope {
    id: root

    IpcHandler {
        target: "clips"

        function toggleViewer(): void {
            Clips.toggleViewer();
        }
        function openViewer(): void {
            Clips.openViewer("");
        }
        function openClip(id: string): void {
            Clips.openViewer(id);
        }
        function start(): void {
            Clips.start();
        }
        function stop(): void {
            Clips.stop();
        }
        function toggle(): void {
            Clips.toggle();
        }
        function save(): void {
            Clips.saveClip();
        }
        function saveBuffer(): void {
            Clips.saveBuffer();
        }
    }

    CompositorGlobalShortcut {
        name: "clipSave"
        description: "Save a clip of the last few seconds"
        onPressed: Clips.saveClip()
    }
    CompositorGlobalShortcut {
        name: "clipSaveBuffer"
        description: "Save the whole replay buffer as a clip"
        onPressed: Clips.saveBuffer()
    }
    CompositorGlobalShortcut {
        name: "clipToggle"
        description: "Start or stop clipping"
        onPressed: Clips.toggle()
    }
    CompositorGlobalShortcut {
        name: "clipViewerToggle"
        description: "Open or close the Clips app"
        onPressed: Clips.toggleViewer()
    }
}
