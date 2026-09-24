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
        Layout.preferredHeight: 28

        MouseArea {
            anchors.fill: parent
            onClicked: section.openStack(section.stack ? section.stack.key : "")
        }

        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            height: parent.height
            spacing: Kirigami.Units.smallSpacing

            Text {
                text: section.title
                font.bold: true
                elide: Text.ElideRight
                Layout.fillWidth: true
                color: Kirigami.Theme.textColor
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
            }

        Text {
                text: section.stack ? section.stack.running + " / " + section.stack.containers.length : ""
                color: Kirigami.Theme.textColor
                opacity: 0.6
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }

            Kirigami.Icon {
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                source: "go-next"
                color: Kirigami.Theme.textColor
                opacity: 0.5
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Kirigami.Theme.textColor
        opacity: 0.1
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 2
    }
}