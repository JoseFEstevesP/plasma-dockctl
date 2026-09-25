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
    property string levelFilter: "all"
    property var filterOptions: [
        { key: "all", label: "Todos" },
        { key: "problems", label: "Avisos+" },
        { key: "errors", label: "Errores" }
    ]

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

    function levelOf(line) {
        var lower = line.toLowerCase();
        if (lower.indexOf("error") >= 0 || lower.indexOf("traceback") >= 0
                || lower.indexOf("fatal") >= 0) {
            return "error";
        }
        if (lower.indexOf("warn") >= 0) {
            return "warn";
        }
        if (lower.indexOf("debug") >= 0 || lower.indexOf("trace") >= 0) {
            return "debug";
        }
        if (lower.indexOf("info") >= 0) {
            return "info";
        }
        return "plain";
    }

    function colorFor(level) {
        if (level === "error") {
            return DS.danger;
        }
        if (level === "warn") {
            return DS.warn;
        }
        if (level === "debug") {
            return DS.debug;
        }
        if (level === "info") {
            return DS.info;
        }
        return "#d0d4da";
    }

    function keeps(level) {
        if (logPage.levelFilter === "problems") {
            return level === "error" || level === "warn";
        }
        if (logPage.levelFilter === "errors") {
            return level === "error";
        }
        return true;
    }

    function tokens() {
        var arr = [];
        var raw = String(logPage.logs).replace(/\u001b\[[0-9;]*m/g, "");
        var lines = raw.split("\n");
        for (var i = 0; i < lines.length; i++) {
            var level = logPage.levelOf(lines[i]);
            if (!logPage.keeps(level)) {
                continue;
            }
            arr.push({ color: logPage.colorFor(level), text: lines[i] });
        }
        return arr;
    }

    function hiddenCount() {
        if (logPage.levelFilter === "all" || logPage.logs === "") {
            return 0;
        }
        var total = String(logPage.logs).split("\n").length;
        return Math.max(0, total - logPage.tokens().length);
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

        RowLayout {
            Layout.fillWidth: true
            spacing: 5
            visible: !logPage.loading && logPage.logs !== ""

            Repeater {
                model: logPage.filterOptions

                delegate: ChipButton {
                    required property var modelData
                    text: modelData.label
                    highlighted: logPage.levelFilter === modelData.key
                    onClicked: logPage.levelFilter = modelData.key
                }
            }

            Text {
                Layout.fillWidth: true
                visible: logPage.hiddenCount() > 0
                text: i18n("%1 líneas ocultas", logPage.hiddenCount())
                color: DS.faint
                font.pixelSize: 10
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignRight
            }
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

            Text {
                anchors.centerIn: parent
                visible: !logPage.loading && logPage.error === "" && logPage.logs !== ""
                    && logPage.levelFilter !== "all" && logPage.tokens().length === 0
                text: i18n("Ninguna línea de ese nivel")
                color: DS.subText
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
            }

            Rectangle {
                anchors.fill: parent
                visible: !logPage.loading && logPage.error === "" && logPage.tokens().length > 0
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