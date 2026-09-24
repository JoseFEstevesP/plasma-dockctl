import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "DockStyle.js" as DS

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
        radius: 5
        color: DS.text
        opacity: delegate.hovered ? 0.06 : 0
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
                color: DS.text
                font.pixelSize: 13
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
                color: DS.subText
                font.pixelSize: 11
            }
        }

        RowLayout {
            spacing: 1
            Layout.alignment: Qt.AlignVCenter

            IconButton {
                visible: delegate.container.running
                icon: Qt.resolvedUrl("../images/icons/stop.svg")
                tooltip: i18n("Parar")
                onClicked: delegate.requestAction(delegate.container.name, "stop")
            }

            IconButton {
                visible: !delegate.container.running
                icon: Qt.resolvedUrl("../images/icons/play.svg")
                tooltip: i18n("Iniciar")
                onClicked: delegate.requestAction(delegate.container.name, "start")
            }

            IconButton {
                icon: Qt.resolvedUrl("../images/icons/refresh.svg")
                tooltip: i18n("Reiniciar")
                onClicked: delegate.requestAction(delegate.container.name, "restart")
            }

            IconButton {
                icon: Qt.resolvedUrl("../images/icons/trash.svg")
                tooltip: i18n("Eliminar")
                onClicked: delegate.requestAction(delegate.container.name, "remove")
            }
        }
    }
}