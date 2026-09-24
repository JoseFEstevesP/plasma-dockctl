import QtQuick
import org.kde.kirigami as Kirigami
import "DockStyle.js" as DS

Rectangle {
    id: dot

    property bool running: false
    property string health: ""

    width: 11
    height: 11
    radius: width / 2

    color: {
        if (dot.running) {
            if (dot.health && dot.health !== "healthy") {
                return DS.orange;
            }
            return DS.green;
        }
        return DS.grey;
    }
}