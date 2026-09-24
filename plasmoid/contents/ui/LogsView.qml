import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "DockStyle.js" as DS

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

    function esc(s) {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function renderLogs(raw) {
        var out = "";
        var lines = raw.split("\n");
        for (var i = 0; i < lines.length; i++) {
            var lower = lines[i].toLowerCase();
            var color = DS.subText;
            if (lower.indexOf("error") >= 0 || lower.indexOf("traceback") >= 0 || lower.indexOf("fatal") >= 0) {
                color = DS.danger;
            } else if (lower.indexOf("warn") >= 0) {
                color = DS.warn;
            } else if (lower.indexOf("debug") >= 0) {
                color = DS.debug;
            } else if (lower.indexOf("info") >= 0) {
                color = DS.info;
            }
            out += "<span style=\"color:" + color + "\">" + esc(lines[i]) + "</span>\n";
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

            ChipButton {
                text: i18n("Actualizar")
                icon: Qt.resolvedUrl("../images/icons/refresh.svg")
                onClicked: logPage.refreshRequested()
            }

            ChipButton {
                text: i18n("Copiar")
                icon: Qt.resolvedUrl("../images/icons/copy.svg")
                enabled: logPage.logs !== ""
                accent: true
                onClicked: logPage.copyLogs()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: DS.divider
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
                anchors.centerIn: parent
                visible: logPage.loading
                text: i18n("Cargando logs…")
                color: DS.subText
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
            }

            Text {
                anchors.centerIn: parent
                visible: !logPage.loading && logPage.error !== ""
                text: logPage.error
                color: DS.danger
                width: parent.width - Kirigami.Units.largeSpacing * 2
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }

            Text {
                anchors.centerIn: parent
                visible: !logPage.loading && logPage.error === "" && logPage.logs === ""
                text: i18n("Sin logs")
                color: DS.subText
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
            }

            Rectangle {
                anchors.fill: parent
                visible: !logPage.loading && logPage.error === "" && logPage.logs !== ""
                radius: Kirigami.Units.smallSpacing
                color: DS.logBg
                border.color: DS.logBorder

                Controls.ScrollView {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing

                    Controls.TextArea {
                        text: logPage.renderLogs(logPage.logs)
                        textFormat: TextEdit.RichText
                        readOnly: true
                        wrapMode: TextEdit.NoWrap
                        color: DS.subText
                        selectionColor: DS.accent
                        selectedTextColor: DS.accentText
                        font.family: "monospace"
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        background: null
                    }
                }
            }
        }
    }
}