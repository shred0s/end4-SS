import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower

// Charge, time left and power mode
ColumnLayout {
    id: root
    spacing: 10

    function formatTime(seconds) {
        if (!seconds || seconds <= 0) return "";
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.round((seconds % 3600) / 60);
        return hours > 0 ? Translation.tr("%1 h %2 min").arg(hours).arg(minutes) : Translation.tr("%1 min").arg(minutes);
    }

    PopupHeader {
        Layout.preferredWidth: 340
        icon: Battery.isCharging ? "battery_charging_full" : "battery_full"
        title: Translation.tr("Battery %1%").arg(Math.round(Battery.percentage * 100))
        subtitle: Battery.isCharging
            ? (root.formatTime(Battery.timeToFull) !== "" ? Translation.tr("Full in %1").arg(root.formatTime(Battery.timeToFull)) : Translation.tr("Charging"))
            : (root.formatTime(Battery.timeToEmpty) !== "" ? Translation.tr("%1 left").arg(root.formatTime(Battery.timeToEmpty)) : Translation.tr("On battery"))
    }

    StyledProgressBar {
        Layout.fillWidth: true
        valueBarWidth: 340
        value: Battery.percentage
    }

    StyledText {
        visible: Battery.health > 0
        text: Translation.tr("Health %1%").arg(Math.round(Battery.health))
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }

    StyledText {
        text: Translation.tr("Power mode")
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        PopupToggleTile {
            symbol: "energy_savings_leaf"
            label: Translation.tr("Saver")
            active: PowerProfiles.profile === PowerProfile.PowerSaver
            onClicked: PowerProfiles.profile = PowerProfile.PowerSaver
        }
        PopupToggleTile {
            symbol: "balance"
            label: Translation.tr("Balanced")
            active: PowerProfiles.profile === PowerProfile.Balanced
            onClicked: PowerProfiles.profile = PowerProfile.Balanced
        }
        PopupToggleTile {
            visible: PowerProfiles.hasPerformanceProfile
            symbol: "bolt"
            label: Translation.tr("Performance")
            active: PowerProfiles.profile === PowerProfile.Performance
            onClicked: PowerProfiles.profile = PowerProfile.Performance
        }
    }
}
