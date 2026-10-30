import QtQuick
import qs.services

QuickToggleModel {
    id: root
    name: Translation.tr("Game mode")
    toggled: GameModeService.active
    icon: "gamepad"

    mainAction: () => GameModeService.toggle()

    tooltipText: Translation.tr("Game mode")
}
