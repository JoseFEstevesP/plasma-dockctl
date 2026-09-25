import QtQuick
import org.kde.kirigami as Kirigami
import "DockStyle.js" as DS

Rectangle {
    id: dot

    property bool running: false
    property string health: ""
    property string severity: ""

    width: 11
    height: 11
    radius: width / 2

    color: {
        if (dot.severity) {
            return DS.severityColor(dot.severity);
        }
        if (dot.running) {
            if (dot.health && dot.health !== "healthy") {
                return DS.orange;
            }
            return DS.green;
        }
        return DS.grey;
    }
}