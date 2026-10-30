pragma Singleton

import QtQuick
import Quickshell
import qs.services

/**
 * Widgets that can be placed in the dock or in its corner islands
 * (dock.widgets.{left,start,end,right}). Files are in modules/ii/dock/widgets.
 *
 * tone: the pill color on M3 islands, like the bar's M3 style ("none" for no pill).
 * group: neighbours with the same group merge into one segmented pill.
 */
Singleton {
    id: root

    readonly property var all: [
        { id: "clock", file: "Clock", name: Translation.tr("Clock"), icon: "schedule", tone: "primaryContainer", group: "info" },
        { id: "calendar", file: "Calendar", name: Translation.tr("Calendar"), icon: "calendar_today", tone: "none" },
        { id: "weather", file: "WeatherNow", name: Translation.tr("Weather"), icon: "partly_cloudy_day", tone: "tertiaryContainer", group: "info" },
        { id: "resources", file: "Resources", name: Translation.tr("Resources"), icon: "memory", tone: "tertiaryContainer", group: "info" },
        { id: "networkSpeed", file: "NetworkSpeed", name: Translation.tr("Network speed"), icon: "network_check", tone: "tertiaryContainer", group: "info" },
        { id: "media", file: "MediaPlayer", name: Translation.tr("Media"), icon: "music_note", tone: "none" },
        { id: "mediaControls", file: "MediaControls", name: Translation.tr("Media controls"), icon: "skip_next", tone: "secondaryContainer" },
        { id: "workspaces", file: "Workspaces", name: Translation.tr("Workspaces"), icon: "steppers", tone: "none" },
        { id: "tray", file: "TrayIcons", name: Translation.tr("Tray"), icon: "inbox", tone: "secondaryContainer" },
        { id: "volume", file: "Volume", name: Translation.tr("Volume"), icon: "volume_up", tone: "primary", group: "status" },
        { id: "brightness", file: "BrightnessLevel", name: Translation.tr("Brightness"), icon: "brightness_6", tone: "primary", group: "status" },
        { id: "microphone", file: "Microphone", name: Translation.tr("Microphone"), icon: "mic", tone: "primary", group: "status" },
        { id: "network", file: "NetworkStatus", name: Translation.tr("Network"), icon: "wifi", tone: "primary", group: "status" },
        { id: "bluetooth", file: "BluetoothToggle", name: Translation.tr("Bluetooth"), icon: "bluetooth", tone: "primary", group: "status" },
        { id: "battery", file: "BatteryLevel", name: Translation.tr("Battery"), icon: "battery_full", tone: "primary", group: "status" },
        { id: "keyboardLayout", file: "KeyboardLayout", name: Translation.tr("Keyboard layout"), icon: "keyboard", tone: "primary", group: "status" },
        { id: "notifications", file: "NotificationBell", name: Translation.tr("Notifications"), icon: "notifications", tone: "primary", group: "status" },
        { id: "nightLight", file: "NightLight", name: Translation.tr("Night light"), icon: "nightlight", tone: "primaryContainer", group: "tools" },
        { id: "keepAwake", file: "KeepAwake", name: Translation.tr("Keep awake"), icon: "coffee", tone: "primaryContainer", group: "tools" },
        { id: "darkMode", file: "DarkMode", name: Translation.tr("Dark mode"), icon: "dark_mode", tone: "primaryContainer", group: "tools" },
        { id: "screenshot", file: "Screenshot", name: Translation.tr("Screenshot"), icon: "screenshot_region", tone: "primaryContainer", group: "tools" },
        { id: "screenRecord", file: "ScreenRecord", name: Translation.tr("Screen record"), icon: "screen_record", tone: "primaryContainer", group: "tools" },
        { id: "colorPicker", file: "ColorPicker", name: Translation.tr("Color picker"), icon: "colorize", tone: "primaryContainer", group: "tools" },
        { id: "wallpaper", file: "WallpaperPicker", name: Translation.tr("Wallpaper"), icon: "imagesmode", tone: "primaryContainer", group: "tools" },
        { id: "keyboard", file: "ScreenKeyboard", name: Translation.tr("On-screen keyboard"), icon: "keyboard_alt", tone: "primaryContainer", group: "tools" },
        { id: "search", file: "Search", name: Translation.tr("Search"), icon: "search", tone: "primaryContainer", group: "shell" },
        { id: "leftSidebar", file: "LeftSidebar", name: Translation.tr("Left sidebar"), icon: "left_panel_open", tone: "primaryContainer", group: "shell" },
        { id: "controlCenter", file: "ControlCenter", name: Translation.tr("Control center"), icon: "toggle_on", tone: "primaryContainer", group: "shell" },
        { id: "settings", file: "SettingsButton", name: Translation.tr("Settings"), icon: "settings", tone: "primaryContainer", group: "shell" },
        { id: "updates", file: "UpdatesCount", name: Translation.tr("Updates"), icon: "deployed_code_update", tone: "tertiaryContainer" },
        { id: "power", file: "Power", name: Translation.tr("Session"), icon: "power_settings_new", tone: "primary" },
    ]

    function find(id) {
        return root.all.find(widget => widget.id === id) ?? null;
    }

    function file(id) {
        return root.find(id)?.file ?? "";
    }

    function name(id) {
        return root.find(id)?.name ?? id;
    }

    function used() {
        const zones = Config.options.dock.widgets;
        return [...zones.left, ...zones.start, ...zones.end, ...zones.right];
    }

    function has(id) {
        return root.used().includes(id);
    }

    // Each widget can be used once across the dock and its corners
    function available() {
        const used = root.used();
        return root.all.filter(widget => !used.includes(widget.id));
    }

    // Adds a widget at the front of the dock, or takes it out of every zone
    function setShown(id, shown) {
        const zones = Config.options.dock.widgets;
        if (shown) {
            if (!root.has(id)) zones.start = [id, ...zones.start];
            return;
        }
        for (const zone of ["left", "start", "end", "right"]) {
            if (zones[zone].includes(id)) zones[zone] = zones[zone].filter(widget => widget !== id);
        }
    }

    function migrate() {
        if (!Config.ready) return;
        // The launcher (Launchpad) and Downloads were widgets for a while; they're fixed dock buttons again
        if (root.has("launchpad")) {
            root.setShown("launchpad", false);
            Config.options.dock.showLaunchpadButton = true;
        }
        if (root.has("downloads")) {
            root.setShown("downloads", false);
            Config.options.dock.showDownloadsButton = true;
        }
    }

    Component.onCompleted: root.migrate()

    Connections {
        target: Config
        function onReadyChanged() {
            root.migrate();
        }
    }
}
