import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

Item {
    id: compact

    Layout.minimumWidth: Kirigami.Units.iconSizes.smallMedium
    Layout.minimumHeight: Kirigami.Units.iconSizes.smallMedium
    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium

    Image {
        id: logo
        anchors.fill: parent
        source: Qt.resolvedUrl("../images/docker.svg")
        sourceSize: Qt.size(width, height)
        fillMode: Image.PreserveAspectFit
        smooth: true
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.expanded = !root.expanded
    }
}