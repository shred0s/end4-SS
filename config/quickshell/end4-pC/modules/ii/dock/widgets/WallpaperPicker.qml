import qs
import qs.services
import qs.modules.common

DockWidgetButton {
    id: root
    popup: WallpaperPopup {
        onOpenPicker: () => {
            root.closePopup();
            GlobalStates.wallpaperSelectorOpen = true;
        }
    }
    symbol: "imagesmode"
    tooltipText: Translation.tr("Wallpapers")
}
