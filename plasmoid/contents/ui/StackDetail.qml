import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: stackPage

    anchors.fill: parent

    property var stack: null

    signal back()
    signal refreshRequested()
    signal openDetail(string name)
    signal requestAction(string name, string action)
    signal restartAll()

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        PageHeader {
            title: stackPage.stack ? stackPage.stack.title : ""
            onBack: stackPage.back()
            onRefreshRequested: stackPage.refreshRequested()

            PlasmaComponents.Button {
                text: stackPage.stack ? String(stackPage.stack.containers.length) : ""
                icon.name: "media-playback-restart"
                Controls.ToolTip.visible: hovered
                Controls.ToolTip.text: i18n("Reiniciar todos los contenedores del stack")
                onClicked: stackPage.restartAll()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Kirigami.Theme.textColor
            opacity: 0.15
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !stackPage.stack || stackPage.stack.containers.length === 0

            Text {
                anchors.centerIn: parent
                text: i18n("Sin contenedores en este stack")
                color: Kirigami.Theme.textColor
                opacity: 0.6
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: stackPage.stack && stackPage.stack.containers.length > 0
            clip: true
            contentWidth: width
            contentHeight: rowsCol.implicitHeight
            interactive: rowsCol.implicitHeight > height

            ColumnLayout {
                id: rowsCol
                width: parent.width
                spacing: 2

                Repeater {
                    model: stackPage.stack ? stackPage.stack.containers : []

                    delegate: DockerRow {
                        container: modelData
                        onRequestAction: function(name, action) { stackPage.requestAction(name, action); }
                        onOpenDetail: function(name) { stackPage.openDetail(name); }
                    }
                }
            }
        }
    }
}