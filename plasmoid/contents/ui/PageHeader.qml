import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "DockStyle.js" as DS

RowLayout {
    id: header

    default property alias extraActions: extraArea.data

    property string title: ""
    property string backTooltip: i18n("Volver")
    property string refreshTooltip: i18n("Actualizar")
    property bool showRefresh: true

    signal back()
    signal refreshRequested()

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    IconButton {
        icon: Qt.resolvedUrl("../images/icons/chevron-left.svg")
        tooltip: header.backTooltip
        onClicked: header.back()
    }

    Text {
        text: header.title
        font.bold: true
        elide: Text.ElideRight
        Layout.fillWidth: true
        color: DS.text
        font.pixelSize: 13
    }

    IconButton {
        icon: Qt.resolvedUrl("../images/icons/refresh.svg")
        tooltip: header.refreshTooltip
        visible: header.showRefresh
        onClicked: header.refreshRequested()
    }

    RowLayout {
        id: extraArea
        visible: children.length > 0
        spacing: Kirigami.Units.smallSpacing
    }
}