import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

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
                font.letterSpacing: 0.7
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                elide: Text.ElideRight
                Layout.fillWidth: true
                color: Kirigami.Theme.textColor
                opacity: 0.55
            }

            Text {
                text: section.stack ? section.stack.running + " / " + section.stack.containers.length : ""
                color: Kirigami.Theme.textColor
                opacity: 0.45
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Kirigami.Theme.textColor
        opacity: 0.12
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 2
    }
}