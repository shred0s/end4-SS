import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.models
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

// Spotlight-like search: apps, actions, math and more (the launcher's search)
ColumnLayout {
    id: root
    // Closes the popup after something was launched
    property var onLaunched: () => {}
    property int currentIndex: 0
    readonly property var results: LauncherSearch.results.slice(0, 8)
    spacing: 8

    Component.onCompleted: {
        LauncherSearch.query = "";
        field.forceActiveFocus();
    }
    Component.onDestruction: LauncherSearch.query = ""

    function launch(index) {
        const result = root.results[index];
        if (!result) return;
        result.execute();
        root.onLaunched();
    }

    MaterialTextField {
        id: field
        Layout.preferredWidth: 420
        placeholderText: Translation.tr("Search apps, files, math…")
        focus: true
        onTextChanged: {
            LauncherSearch.query = text;
            root.currentIndex = 0;
        }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Down) {
                root.currentIndex = Math.min(root.results.length - 1, root.currentIndex + 1);
            } else if (event.key === Qt.Key_Up) {
                root.currentIndex = Math.max(0, root.currentIndex - 1);
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.launch(root.currentIndex);
            } else {
                return;
            }
            event.accepted = true;
        }
    }

    Repeater {
        model: root.results
        delegate: RippleButton {
            id: resultButton
            required property var modelData
            required property int index
            readonly property bool current: index === root.currentIndex
            Layout.fillWidth: true
            implicitHeight: 46
            horizontalPadding: 10
            buttonRadius: Appearance.rounding.small
            colBackground: current ? Appearance.colors.colSecondaryContainer : "transparent"
            colBackgroundHover: current ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
            onHoveredChanged: if (hovered) root.currentIndex = index
            onClicked: root.launch(index)

            contentItem: RowLayout {
                spacing: 10
                Item {
                    implicitWidth: 28
                    implicitHeight: 28
                    IconImage {
                        anchors.fill: parent
                        visible: resultButton.modelData.iconType === LauncherSearchResult.IconType.System
                        source: visible ? SystemAppearance.iconPath(resultButton.modelData.iconName, "application-x-executable") : ""
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: resultButton.modelData.iconType !== LauncherSearchResult.IconType.System
                        text: resultButton.modelData.iconType === LauncherSearchResult.IconType.Material ? resultButton.modelData.iconName : "search"
                        iconSize: 22
                        color: Appearance.colors.colOnLayer2
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: -2
                    StyledText {
                        Layout.fillWidth: true
                        text: resultButton.modelData.name
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: resultButton.current ? Appearance.colors.colOnSecondaryContainer : Appearance.m3colors.m3onSurface
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: resultButton.modelData.type ?? ""
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
                StyledText {
                    visible: resultButton.current
                    text: resultButton.modelData.verb ?? ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
