pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "customImage"
    hoverEnabled: true

    // -1 is the base customImage entry, otherwise an index into customImage.instances
    property int instanceIndex: -1
    readonly property bool isPrimary: instanceIndex < 0
    configEntry: isPrimary
        ? Config.options.background.widgets.customImage
        // Fallback only matters briefly while a removed instance's delegate is torn down
        : (Config.options.background.widgets.customImage.instances[instanceIndex] ?? Config.options.background.widgets.customImage)

    property string imagePath: configEntry.path ?? ""
    property bool dropHover: false
    property int shapeType: ShapeUtils.getShape(configEntry.shape ?? "Cookie4Sided")
    property real widgetSize: configEntry.size ?? 200

    readonly property var acceptedExtensions: ["png","jpg","jpeg","webp","avif","bmp","gif","tiff","tif"]

    function writeConfig(changes) {
        if (root.isPrimary) {
            for (const key in changes) configEntry[key] = changes[key];
        } else {
            DesktopWidgets.updateCustomImage(root.instanceIndex, changes);
        }
    }

    function requestDelete() {
        if (root.isPrimary) Config.options.background.widgets.customImage.enable = false;
        else DesktopWidgets.removeCustomImage(root.instanceIndex);
    }

    function rightClicked(mouse) {
        if (GlobalStates.screenLocked) return;
        // The menu closes through HyprlandFocusGrab; elsewhere go straight to the picker
        if (WM.compositor !== "hyprland") {
            root.chooseImage();
            return;
        }
        contextMenu.open(root, mouse.x, mouse.y);
    }

    function chooseImage() {
        if (imagePickerProc.running) return;
        const current = FileUtils.trimFileProtocol(root.imagePath);
        imagePickerProc.startDir = current !== ""
            ? current.substring(0, current.lastIndexOf("/"))
            : FileUtils.trimFileProtocol(Directories.pictures);
        imagePickerProc.running = true;
    }

    Process {
        id: imagePickerProc
        property string startDir: ""
        command: ["bash", "-c",
            'if command -v kdialog >/dev/null; then kdialog --title "$1" --getopenfilename "$2" "$3"; '
            + 'else zenity --file-selection --title="$1" --filename="$2/" --file-filter="$4"; fi',
            "_",
            Translation.tr("Choose image"),
            startDir,
            "Images (" + root.acceptedExtensions.map(e => "*." + e).join(" ") + ")",
            "Images | " + root.acceptedExtensions.map(e => "*." + e).join(" ")]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim();
                if (path !== "") root.writeConfig({ path: path });
            }
        }
    }

    CustomImageContextMenu {
        id: contextMenu
        hasImage: root.imagePath !== ""
        onChooseImageRequested: root.chooseImage()
        onClearImageRequested: root.writeConfig({ path: "" })
        onAddImageRequested: DesktopWidgets.addCustomImage(root.configEntry)
        onRemoveRequested: root.requestDelete()
    }

    implicitWidth: contentItem.implicitWidth
    implicitHeight: contentItem.implicitHeight

    Item {
        id: contentItem
        implicitWidth: root.widgetSize
        implicitHeight: root.widgetSize

        Behavior on implicitWidth {
            animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
        }
        Behavior on implicitHeight {
            animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
        }

        MaterialShape {
            id: shadowShape
            anchors.fill: parent
            color: Appearance.colors.colPrimaryContainer
            shape: root.shapeType
            visible: false
        }

        StyledDropShadow {
            target: shadowShape
            z: -1
            visible: Config.options.background.widgets.shadow
        }

        MaterialShape {
            id: imageShape
            anchors.fill: parent
            z: 0
            color: Appearance.colors.colPrimaryContainer
            shape: root.shapeType

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: MaterialShape {
                    width: imageShape.width
                    height: imageShape.height
                    shape: root.shapeType
                }
            }

            StyledImage {
                anchors.fill: parent
                source: root.imagePath !== "" ? root.imagePath : ""
                fillMode: Image.PreserveAspectCrop
                cache: false
                antialiasing: true
                sourceSize.width: parent.width
                sourceSize.height: parent.height
                visible: root.imagePath !== ""
            }

            // Placeholder + hover hint
            MaterialSymbol {
                anchors.centerIn: parent
                iconSize: contentItem.implicitWidth / 3
                text: root.dropHover ? "download" : "image"
                fill: root.dropHover ? 1 : 0
                color: root.dropHover
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colOnPrimaryContainer
                visible: root.imagePath === ""
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            }

            DropArea {
                anchors.fill: parent
                keys: ["text/uri-list"]
                onEntered: (drag) => {
                    drag.accept(Qt.CopyAction)
                    root.dropHover = true
                }
                onExited: {
                    root.dropHover = false
                }
                onDropped: (drop) => {
                    if (drop.hasUrls && drop.urls.length > 0) {
                        var cleanPath = drop.urls[0].toString().replace(/^file:\/\//, "")
                        var ext = cleanPath.split(".").pop().toLowerCase()
                        if (root.acceptedExtensions.indexOf(ext) !== -1) {
                            root.writeConfig({ path: cleanPath })
                        }
                    }
                    root.dropHover = false
                }
            }
        }

        ResizeHandler{
            anchorItem: imageShape
            hoverActive: root.containsMouse
            locked: Config.options.background.widgetsLocked
            currentWidth: root.widgetSize
            resizeMode: "diagonal"
            z: 1
            onResized: (newValue) => {
                root.widgetSize = Math.max(80, newValue)
            }
            onResizeFinished: {
                root.writeConfig({ size: root.widgetSize })
            }
        }
    }
}
