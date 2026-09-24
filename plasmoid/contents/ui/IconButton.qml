import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "DockStyle.js" as DS

Rectangle {
    id: iconBtn

    property string icon: ""
    property string tooltip: ""
    property bool active: true
    property bool hovered: false
    property color iconColor: DS.icon

    signal clicked()

    implicitWidth: 22
    implicitHeight: 22
    radius: 4
    color: iconBtn.hovered ? DS.chipHover : "transparent"

    Kirigami.Icon {
        anchors.centerIn: parent
        width: 15
        height: 15
        source: iconBtn.icon
        color: iconBtn.iconColor
        visible: iconBtn.active
        opacity: iconBtn.active ? 1 : 0.4
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: iconBtn.active
        onEntered: iconBtn.hovered = true
        onExited: iconBtn.hovered = false
        onClicked: iconBtn.clicked()
    }

    Controls.ToolTip.visible: iconBtn.hovered && iconBtn.tooltip !== ""
    Controls.ToolTip.text: iconBtn.tooltip
    Controls.ToolTip.delay: 400
}