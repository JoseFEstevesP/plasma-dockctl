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

    function tokens() {
        var arr = [];
        var raw = String(logPage.logs).replace(/\u001b\[[0-9;]*m/g, "");
        var lines = raw.split("\n");
        for (var i = 0; i < lines.length; i++) {
            var lower = lines[i].toLowerCase();
            var c = "#d0d4da";
            if (lower.indexOf("error") >= 0 || lower.indexOf("traceback") >= 0 || lower.indexOf("fatal") >= 0) {
                c = DS.danger;
            } else if (lower.indexOf("warn") >= 0) {
                c = DS.warn;
            } else if (lower.indexOf("debug") >= 0) {
                c = DS.debug;
            } else if (lower.indexOf("info") >= 0) {
                c = DS.info;
            }
            arr.push({ color: c, text: lines[i] });
        }
        return arr;
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
                clip: true

                ListView {
                    id: logList
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing
                    anchors.rightMargin: Kirigami.Units.smallSpacing - 2
                    clip: true
                    spacing: 1
                    model: logPage.tokens()

                    Controls.ScrollBar.vertical: Controls.ScrollBar {
                        policy: Controls.ScrollBar.AsNeeded
                        width: 4
                        anchors.margins: 1
                    }

                    delegate: Text {
                        width: logList.width - Kirigami.Units.largeSpacing
                        color: modelData.color
                        text: modelData.text
                        font.family: "monospace"
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        wrapMode: Text.Wrap
                        lineHeight: 1.25
                    }
                }
            }
        }
    }
}