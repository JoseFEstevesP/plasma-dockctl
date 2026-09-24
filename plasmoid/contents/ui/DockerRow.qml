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
    signal requestAction(string name, string action)
    signal openDetail(string name)

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
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
                text: delegate.container.stack && (delegate.container.stack + " / ") + delegate.container.name
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
                opacity: 0.7
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

            PlasmaComponents.ToolButton {
                hoverEnabled: true
                icon.name: "go-next"
                Controls.ToolTip.visible: hovered
                Controls.ToolTip.text: i18n("Detalles y logs")
                onClicked: delegate.openDetail(delegate.container.name)
            }
        }
    }
}