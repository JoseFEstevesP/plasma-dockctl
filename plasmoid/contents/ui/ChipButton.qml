import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "DockStyle.js" as DS

Rectangle {
    id: chip

    property string text: ""
    property string icon: ""
    property bool accent: false
    property bool enabled: true
    property bool highlighted: false
    property int maxTextWidth: 9999
    property color iconColor: chip.accent ? DS.accentText
        : (chip.enabled ? DS.subText : DS.faint)

    signal clicked()

    implicitWidth: contentRow.implicitWidth + 20
    implicitHeight: 26
    radius: 4
    color: {
        if (!chip.enabled) {
            return DS.chipBg;
        }
        if (chip.highlighted) {
            return chip.accent ? DS.accentHover : DS.chipHover;
        }
        return chip.accent ? DS.accent : DS.chipBg;
    }

    RowLayout {
        id: contentRow
        anchors.centerIn: parent
        spacing: 5

        Kirigami.Icon {
            visible: chip.icon !== ""
            Layout.preferredWidth: 13
            Layout.preferredHeight: 13
            source: chip.icon
            color: chip.iconColor
        }

        Text {
            text: chip.text
            color: chip.accent
                ? DS.accentText
                : (chip.enabled ? DS.text : DS.faint)
            font.pixelSize: 12
            elide: Text.ElideRight
            Layout.maximumWidth: chip.maxTextWidth
            verticalAlignment: Text.AlignVCenter
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: chip.enabled
        onEntered: chip.highlighted = true
        onExited: chip.highlighted = false
        onClicked: chip.clicked()
    }
}