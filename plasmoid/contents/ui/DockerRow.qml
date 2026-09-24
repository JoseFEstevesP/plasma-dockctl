import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: delegate

    Layout.fillWidth: true
    height: Math.max(layout.implicitHeight, 40)

    property var container: ({})
    property bool hovered: false

    signal requestAction(string name, string action)
    signal openDetail(string name)

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: Kirigami.Theme.textColor
        opacity: delegate.hovered ? 0.07 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        onEntered: delegate.hovered = true
        onExited: delegate.hovered = false
        onClicked: delegate.openDetail(delegate.container.name)
    }

    RowLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Kirigami.Units.smallSpacing

        StatusDot {
            Layout.alignment: Qt.AlignVCenter
            running: delegate.container.running
            health: delegate.container.health
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 1

            Text {
                text: delegate.container.name || ""
                elide: Text.ElideRight
                Layout.fillWidth: true
                font.bold: true
                color: Kirigami.Theme.textColor
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
            }

            Text {
                text: {
                    var parts = [];
                    if (delegate.container.image) {
                        parts.push(delegate.container.image);
                    }
                    if (delegate.container.status) {
                        parts.push(delegate.container.status);
                    }
                    if (delegate.container.ports) {
                        parts.push(delegate.container.ports);
                    }
                    return parts.join("  •  ");
                }
                elide: Text.ElideRight
                Layout.fillWidth: true
                color: Kirigami.Theme.textColor
                opacity: 0.65
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }
        }

        RowLayout {
            spacing: 1
            Layout.alignment: Qt.AlignVCenter

            PlasmaComponents.ToolButton {
                visible: delegate.container.running
                hoverEnabled: true
                icon.name: "media-playback-stop"
                Controls.ToolTip.visible: hovered
                Controls.ToolTip.text: i18n("Parar")
                onClicked: delegate.requestAction(delegate.container.name, "stop")
            }

            PlasmaComponents.ToolButton {
                visible: !delegate.container.running
                hoverEnabled: true
                icon.name: "media-playback-start"
                Controls.ToolTip.visible: hovered
                Controls.ToolTip.text: i18n("Iniciar")
                onClicked: delegate.requestAction(delegate.container.name, "start")
            }

            PlasmaComponents.ToolButton {
                hoverEnabled: true
                icon.name: "view-refresh"
                Controls.ToolTip.visible: hovered
                Controls.ToolTip.text: i18n("Reiniciar")
                onClicked: delegate.requestAction(delegate.container.name, "restart")
            }

            PlasmaComponents.ToolButton {
                hoverEnabled: true
                icon.name: "edit-delete"
                Controls.ToolTip.visible: hovered
                Controls.ToolTip.text: i18n("Eliminar")
                onClicked: delegate.requestAction(delegate.container.name, "remove")
            }
        }
    }
}