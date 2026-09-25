import QtQuick
import "DockStyle.js" as DS

Rectangle {
    id: miniBar

    property real value: 0
    property color fillColor: DS.accent

    implicitHeight: 4
    radius: height / 2
    color: DS.barBg

    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        width: Math.max(0, Math.min(1, miniBar.value)) * parent.width
        radius: parent.radius
        color: miniBar.fillColor
        Behavior on width {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
        }
    }
}
