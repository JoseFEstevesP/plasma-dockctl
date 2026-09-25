import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "DockStyle.js" as DS

Item {
    id: detailPage

    anchors.fill: parent

    property var container: null
    property var detailData: null
    property bool loading: false
    property string error: ""

    readonly property var diagnostics: (detailData && detailData.diagnostics)
        ? detailData.diagnostics : []

    readonly property string worstSeverity: {
        var worst = "";
        for (var i = 0; i < detailPage.diagnostics.length; i++) {
            var sev = detailPage.diagnostics[i].severity || "";
            if (sev === "critical") {
                return "critical";
            }
            if (sev === "warn") {
                worst = "warn";
            }
        }
        return worst;
    }

    signal back()
    signal refreshRequested()
    signal requestAction(string name, string action)
    signal openLogs(string name)
    signal topRequested()

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        PageHeader {
            title: detailPage.container ? detailPage.container.name : ""
            onBack: detailPage.back()
            onRefreshRequested: detailPage.refreshRequested()
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: DS.divider
        }

        Item {
            id: contentArea
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
                anchors.centerIn: parent
                visible: detailPage.loading
                text: i18n("Cargando detalles…")
                color: DS.subText
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
            }

            Text {
                anchors.centerIn: parent
                visible: !detailPage.loading && detailPage.error !== ""
                text: detailPage.error
                color: DS.danger
                width: parent.width - Kirigami.Units.largeSpacing * 2
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }

            Flickable {
                id: scroll
                anchors.fill: contentArea
                visible: !detailPage.loading && detailPage.error === "" && detailPage.detailData
                clip: true
                contentWidth: width
                contentHeight: infoCol.implicitHeight
                interactive: contentHeight > height

                ColumnLayout {
                    id: infoCol
                    width: scroll.width
                    spacing: 4

                    Row {
                        spacing: Kirigami.Units.smallSpacing
                        Layout.alignment: Qt.AlignLeft

                        StatusDot {
                            anchors.verticalCenter: parent.verticalCenter
                            running: detailPage.detailData ? detailPage.detailData.running : false
                            health: detailPage.detailData ? detailPage.detailData.health : ""
                            severity: detailPage.worstSeverity
                        }

                        Text {
                            text: {
                                if (!detailPage.detailData) {
                                    return "";
                                }
                                var d = detailPage.detailData;
                                var s = d.state || "";
                                if (d.health) {
                                    s += "  ·  " + (d.health === "healthy" ? i18n("saludable") : d.health);
                                }
                                return s;
                            }
                            color: stateColor(detailPage.detailData)
                            font.bold: true
                            font.pixelSize: 13
                        }
                    }

                    Text {
                        visible: detailPage.diagnostics.length > 0
                        text: i18n("Diagnóstico")
                        font.bold: true
                        color: DS.text
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        Layout.topMargin: 6
                    }

                    Repeater {
                        model: detailPage.diagnostics

                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 6

                            StatusDot {
                                severity: modelData.severity
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modelData.text
                                color: DS.subText
                                font.pixelSize: 11
                                wrapMode: Text.Wrap
                            }
                        }
                    }

                    InfoLine { label: i18n("Imagen"); value: detailPage.detailData ? detailPage.detailData.image : "" }
                    InfoLine { label: i18n("Stack"); value: detailPage.detailData && detailPage.detailData.stack ? detailPage.detailData.stack : "—" }
                    InfoLine { label: i18n("Reinicios"); value: detailPage.detailData ? String(detailPage.detailData.restartCount) : "0" }
                    InfoLine { label: i18n("Creado"); value: detailPage.detailData ? detailPage.detailData.created : "" }
                    InfoLine { label: i18n("Iniciado"); value: detailPage.detailData ? detailPage.detailData.startedAt : "" }

                    Text {
                        visible: detailPage.detailData && (detailPage.detailData.ips || []).length === 0
                        text: i18n("Sin IP de red propia")
                        color: DS.subText
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    }

                    Repeater {
                        model: detailPage.detailData ? detailPage.detailData.ips : []
                        delegate: InfoLine {
                            label: modelData.network
                            value: modelData.ip
                        }
                    }

                    Text {
                        visible: detailPage.detailData && (detailPage.detailData.ports || []).length > 0
                        text: i18n("Puertos")
                        font.bold: true
                        color: DS.text
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        Layout.topMargin: 4
                    }

                    Repeater {
                        model: detailPage.detailData ? detailPage.detailData.ports : []
                        delegate: InfoLine {
                            label: modelData.host_ip + ":" + modelData.host_port
                            value: "→  " + modelData.container
                        }
                    }

                    Text {
                        visible: detailPage.detailData && (detailPage.detailData.ports || []).length === 0
                        text: i18n("Sin puertos publicados")
                        color: DS.subText
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    }

                    Item { Layout.preferredHeight: Kirigami.Units.smallSpacing * 2 }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        ChipButton {
                            text: detailPage.detailData && detailPage.detailData.running
                                    ? i18n("Parar")
                                    : i18n("Iniciar")
                            icon: detailPage.detailData && detailPage.detailData.running
                                        ? Qt.resolvedUrl("../images/icons/stop.svg")
                                        : Qt.resolvedUrl("../images/icons/play.svg")
                            accent: true
                            onClicked: detailPage.requestAction(detailPage.container.name,
                                detailPage.detailData && detailPage.detailData.running ? "stop" : "start")
                        }

                        ChipButton {
                            text: i18n("Reiniciar")
                            icon: Qt.resolvedUrl("../images/icons/refresh.svg")
                            onClicked: detailPage.requestAction(detailPage.container.name, "restart")
                        }

                        ChipButton {
                            text: i18n("Eliminar")
                            icon: Qt.resolvedUrl("../images/icons/trash.svg")
                            onClicked: detailPage.requestAction(detailPage.container.name, "remove")
                        }

                        Item { Layout.fillWidth: true }

                        ChipButton {
                            text: i18n("Procesos")
                            icon: Qt.resolvedUrl("../images/icons/list.svg")
                            visible: detailPage.detailData && detailPage.detailData.running
                            onClicked: detailPage.topRequested()
                        }

                        ChipButton {
                            text: i18n("Ver logs")
                            icon: Qt.resolvedUrl("../images/icons/logs.svg")
                            onClicked: detailPage.openLogs(detailPage.container.name)
                        }
                    }
                }
            }
        }
    }

    function stateColor(d) {
        if (!d) {
            return DS.subText;
        }
        if (d.running) {
            if (d.health && d.health !== "healthy") {
                return DS.warn;
            }
            return DS.green;
        }
        return DS.subText;
    }

    component InfoLine: RowLayout {
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Text {
            text: parent && parent.label
            width: 72
            elide: Text.ElideRight
            color: DS.subText
            font.pixelSize: 11
        }

        Text {
            text: parent && parent.value
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: DS.text
            font.bold: true
            font.pixelSize: 11
        }
    }
}