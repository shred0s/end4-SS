import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// Icon button (e.g. mute) + slider + percentage
RowLayout {
    id: root
    property string icon
    property real value: 0
    property real from: 0
    property real to: 1
    property bool iconToggled: false
    signal moved(real value)
    signal iconClicked()

    spacing: 8

    RippleButton {
        implicitWidth: 36
        implicitHeight: 36
        buttonRadius: width / 2
        toggled: root.iconToggled
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        onClicked: root.iconClicked()
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: root.icon
            iconSize: 20
            fill: 1
            color: root.iconToggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
        }
    }

    StyledSlider {
        id: slider
        Layout.fillWidth: true
        from: root.from
        to: root.to
        value: root.value
        configuration: StyledSlider.Configuration.S
        onMoved: root.moved(slider.value)
    }

    StyledText {
        Layout.preferredWidth: 38
        horizontalAlignment: Text.AlignRight
        text: `${Math.round((root.value - root.from) / Math.max(0.0001, root.to - root.from) * 100)}%`
        font.pixelSize: Appearance.font.pixelSize.small
        font.features: { "tnum": 1 }
        color: Appearance.colors.colSubtext
    }
}
