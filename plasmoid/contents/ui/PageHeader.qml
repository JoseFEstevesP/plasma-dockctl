import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

RowLayout {
    id: header

    default property alias extraActions: extraArea.data

    property string title: ""
    property string backTooltip: i18n("Volver")
    property string refreshTooltip: i18n("Actualizar")

    signal back()
    signal refreshRequested()

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    PlasmaComponents.ToolButton {
        hoverEnabled: true
        icon.name: "go-previous"
        Controls.ToolTip.visible: hovered
        Controls.ToolTip.text: header.backTooltip
        onClicked: header.back()
    }

    Text {
        text: header.title
        font.bold: true
        elide: Text.ElideRight
        Layout.fillWidth: true
        color: Kirigami.Theme.textColor
        font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
    }

    PlasmaComponents.ToolButton {
        hoverEnabled: true
        icon.name: "view-refresh"
        Controls.ToolTip.visible: hovered
        Controls.ToolTip.text: header.refreshTooltip
        onClicked: header.refreshRequested()
    }

    RowLayout {
        id: extraArea
        visible: children.length > 0
        spacing: Kirigami.Units.smallSpacing
    }
}