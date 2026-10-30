import qs.services
import qs.modules.common

DockWidgetButton {
    symbol: "nightlight"
    symbolFill: Hyprsunset.temperatureActive
    active: Hyprsunset.temperatureActive
    tooltipText: Hyprsunset.temperatureActive ? Translation.tr("Night light on") : Translation.tr("Night light off")
    onClicked: Hyprsunset.toggleTemperature()
}
