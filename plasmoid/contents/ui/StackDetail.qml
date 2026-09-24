import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "DockStyle.js" as DS

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

            ChipButton {
                text: stackPage.stack ? i18n("Reiniciar · %1", stackPage.stack.containers.length) : ""
                icon: Qt.resolvedUrl("../images/icons/refresh.svg")
                accent: true
                onClicked: stackPage.restartAll()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: DS.divider
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !stackPage.stack || stackPage.stack.containers.length === 0

            Text {
                anchors.centerIn: parent
                text: i18n("Sin contenedores en este stack")
                color: DS.subText
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