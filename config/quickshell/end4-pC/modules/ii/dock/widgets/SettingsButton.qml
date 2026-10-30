import qs
import qs.services
import qs.modules.common

DockWidgetButton {
    id: root
    popup: SettingsPopup {
        onOpenSettings: () => {
            root.closePopup();
            GlobalStates.settingsOpen = true;
        }
    }
    symbol: "settings"
    tooltipText: Translation.tr("Settings")
}
