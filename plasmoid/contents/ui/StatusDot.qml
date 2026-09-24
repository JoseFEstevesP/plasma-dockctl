import QtQuick
import org.kde.kirigami as Kirigami

Rectangle {
    id: dot

    property bool running: false
    property string health: ""

    width: Kirigami.Units.iconSizes.tiny
    height: width
    radius: width / 2

    color: {
        if (dot.running) {
            if (dot.health && dot.health !== "healthy") {
                return Kirigami.Theme.neutralTextColor;
            }
            return Kirigami.Theme.positiveTextColor;
        }
        var base = Kirigami.Theme.textColor;
        return Qt.rgba(base.r, base.g, base.b, 0.35);
    }
}