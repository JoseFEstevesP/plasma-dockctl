import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "DockStyle.js" as DS

ColumnLayout {
    id: section

    Layout.fillWidth: true
    spacing: 2

    property var stack: ({})
    readonly property string title: stack.title || ""

    signal openStack(string key)

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 24

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: section.openStack(section.stack ? section.stack.key : "")
        }

        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            height: parent.height
            spacing: Kirigami.Units.smallSpacing

            Text {
                text: section.title.toUpperCase()
                font.bold: true
                font.letterSpacing: 0.5
                font.pixelSize: 12
                elide: Text.ElideRight
                Layout.fillWidth: true
                color: DS.subText
            }

            Text {
                text: section.stack ? section.stack.running + " / " + section.stack.containers.length : ""
                color: DS.faint
                font.pixelSize: 11
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: DS.divider
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 2
    }
}