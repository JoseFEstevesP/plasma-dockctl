import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: logPage

    anchors.fill: parent

    property string containerName: ""
    property string logs: ""
    property bool loading: false
    property string error: ""

    signal back()
    signal refreshRequested()

    TextEdit {
        id: clipSource
        visible: false
        text: logPage.logs
    }

    function copyLogs() {
        if (logPage.logs === "") {
            return;
        }
        clipSource.selectAll();
        clipSource.copy();
    }

    function colorString(c) {
        return "#"
            + Math.round(c.r * 255).toString(16).padStart(2, "0")
            + Math.round(c.g * 255).toString(16).padStart(2, "0")
            + Math.round(c.b * 255).toString(16).padStart(2, "0");
    }

    function esc(s) {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function renderLogs(raw) {
        var out = "";
        var lines = raw.split("\n");
        for (var i = 0; i < lines.length; i++) {
            var lower = lines[i].toLowerCase();
            var color = "";
            if (lower.indexOf("error") >= 0 || lower.indexOf("traceback") >= 0) {
                color = colorString(Kirigami.Theme.negativeTextColor);
            } else if (lower.indexOf("warn") >= 0) {
                color = colorString(Kirigami.Theme.neutralTextColor);
            } else if (lower.indexOf("debug") >= 0) {
                color = colorString(Kirigami.Theme.highlightColor);
            }
            out += (color !== "")
                ? "<span style=\"color:" + color + "\">" + esc(lines[i]) + "</span>\n"
                : esc(lines[i]) + "\n";
        }
        return out;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        PageHeader {
            title: logPage.containerName
            backTooltip: i18n("Volver al detalle")
            showRefresh: false
            onBack: logPage.back()
            onRefreshRequested: logPage.refreshRequested()

            PlasmaComponents.Button {
                text: i18n("Actualizar")
                icon.name: "view-refresh"
                onClicked: logPage.refreshRequested()
            }

            PlasmaComponents.Button {
                text: i18n("Copiar")
                icon.name: "edit-copy"
                enabled: logPage.logs !== ""
                onClicked: logPage.copyLogs()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Kirigami.Theme.textColor
            opacity: 0.15
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
                anchors.centerIn: parent
                visible: logPage.loading
                text: i18n("Cargando logs…")
                color: Kirigami.Theme.textColor
                opacity: 0.6
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
            }

            Text {
                anchors.centerIn: parent
                visible: !logPage.loading && logPage.error !== ""
                text: logPage.error
                color: Kirigami.Theme.negativeTextColor
                width: parent.width - Kirigami.Units.largeSpacing * 2
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }

            Text {
                anchors.centerIn: parent
                visible: !logPage.loading && logPage.error === "" && logPage.logs === ""
                text: i18n("Sin logs")
                color: Kirigami.Theme.textColor
                opacity: 0.6
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
            }

            Rectangle {
                anchors.fill: parent
                visible: !logPage.loading && logPage.error === "" && logPage.logs !== ""
                radius: Kirigami.Units.smallSpacing
                color: Kirigami.Theme.alternateBackgroundColor
                border.color: Qt.rgba(Kirigami.Theme.textColor.r,
                                      Kirigami.Theme.textColor.g,
                                      Kirigami.Theme.textColor.b, 0.18)

                Controls.ScrollView {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing

                    Controls.TextArea {
                        text: logPage.renderLogs(logPage.logs)
                        textFormat: TextEdit.RichText
                        readOnly: true
                        wrapMode: TextEdit.NoWrap
                        color: Kirigami.Theme.textColor
                        selectionColor: Kirigami.Theme.highlightColor
                        selectedTextColor: Kirigami.Theme.highlightedTextColor
                        font.family: "monospace"
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        background: null
                    }
                }
            }
        }
    }
}