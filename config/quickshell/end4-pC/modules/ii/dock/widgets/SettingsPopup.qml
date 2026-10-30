import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

// Quick shell settings; the full Settings app is a button away
ColumnLayout {
    id: root
    property var onOpenSettings: () => {}
    spacing: 8

    component ChoiceRow: ColumnLayout {
        id: choice
        property string title
        property var options: []
        property var current
        signal picked(var value)
        Layout.fillWidth: true
        spacing: 4
        StyledText {
            text: choice.title
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
        RowLayout {
            spacing: 4
            Repeater {
                model: choice.options
                delegate: RippleButton {
                    required property var modelData
                    readonly property bool selected: modelData.value === choice.current
                    Layout.fillWidth: true
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.small
                    colBackground: selected ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                    colBackgroundHover: selected ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                    onClicked: choice.picked(modelData.value)
                    contentItem: StyledText {
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData.name
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                    }
                }
            }
        }
    }

    PopupHeader {
        Layout.preferredWidth: 380
        icon: "settings"
        title: Translation.tr("Quick settings")
    }

    ChoiceRow {
        title: Translation.tr("Dock style")
        current: Config.options.dock.style
        options: [
            { name: Translation.tr("Float"), value: "float" },
            { name: Translation.tr("Hug"), value: "hug" },
            { name: Translation.tr("Islands"), value: "islands" },
            { name: Translation.tr("M3"), value: "m3" },
            { name: Translation.tr("Panel"), value: "panel" }
        ]
        onPicked: value => Config.options.dock.style = value
    }
    ChoiceRow {
        title: Translation.tr("Dock position")
        current: Config.options.dock.position
        options: [
            { name: Translation.tr("Left"), value: "left" },
            { name: Translation.tr("Bottom"), value: "bottom" },
            { name: Translation.tr("Right"), value: "right" }
        ]
        onPicked: value => Config.options.dock.position = value
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        rowSpacing: 6
        columnSpacing: 6
        PopupToggleTile {
            symbol: "zoom_in"
            label: Translation.tr("Magnification")
            active: Config.options.dock.magnify
            onClicked: Config.options.dock.magnify = !Config.options.dock.magnify
        }
        PopupToggleTile {
            symbol: "highlight_mouse_cursor"
            label: Translation.tr("Auto-hide dock")
            active: Config.options.dock.hoverToReveal
            onClicked: Config.options.dock.hoverToReveal = !Config.options.dock.hoverToReveal
        }
        PopupToggleTile {
            symbol: "opacity"
            label: Translation.tr("Transparency")
            active: Config.options.appearance.transparency.enable
            onClicked: Config.options.appearance.transparency.enable = !Config.options.appearance.transparency.enable
        }
        PopupToggleTile {
            symbol: Appearance.m3colors.darkmode ? "dark_mode" : "light_mode"
            label: Translation.tr("Dark mode")
            active: Appearance.m3colors.darkmode
            onClicked: Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --mode ${Appearance.m3colors.darkmode ? "light" : "dark"} --noswitch`])
        }
    }

    DialogButton {
        Layout.alignment: Qt.AlignRight
        buttonText: Translation.tr("All settings")
        onClicked: root.onOpenSettings()
    }
}
