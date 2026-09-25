import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "DockStyle.js" as DS

Item {
    id: analysisPage

    anchors.fill: parent

    property var analysis: null
    property bool loading: false
    property string error: ""

    signal back()
    signal refreshRequested()
    signal requestMaintain(string target, string title, string subtitle, string confirmText)

    readonly property var summary: (analysis && analysis.summary) ? analysis.summary : ({})
    readonly property var findings: (analysis && analysis.findings) ? analysis.findings : []
    readonly property int reclaimableBytes: summary.reclaimBytes || 0

    TextEdit {
        id: clipSource
        visible: false
    }

    function copyText(text) {
        if (!text) {
            return;
        }
        clipSource.text = text;
        clipSource.selectAll();
        clipSource.copy();
    }

    function targetsText(finding) {
        if (!finding || !finding.targets || finding.targets.length === 0) {
            return "";
        }
        var txt = finding.targets.join(", ");
        if (finding.targetCount > finding.targets.length) {
            txt += i18n(" (+%1 más)", finding.targetCount - finding.targets.length);
        }
        return txt;
    }

    function fmtBytes(count) {
        if (!count || count <= 0) {
            return "0 B";
        }
        if (count >= 1073741824) {
            return (count / 1073741824).toFixed(1) + " GB";
        }
        if (count >= 1048576) {
            return (count / 1048576).toFixed(0) + " MB";
        }
        if (count >= 1024) {
            return (count / 1024).toFixed(0) + " kB";
        }
        return count + " B";
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        PageHeader {
            title: i18n("Análisis")
            refreshTooltip: i18n("Volver a medir")
            onBack: analysisPage.back()
            onRefreshRequested: analysisPage.refreshRequested()
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
                visible: analysisPage.loading
                text: i18n("Analizando disco y contenedores…\n(puede tardar unos segundos)")
                color: DS.subText
                width: parent.width - Kirigami.Units.largeSpacing * 2
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }

            Text {
                anchors.centerIn: parent
                visible: !analysisPage.loading && analysisPage.error !== ""
                text: analysisPage.error
                color: DS.danger
                width: parent.width - Kirigami.Units.largeSpacing * 2
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }

            Flickable {
                id: scroll
                anchors.fill: parent
                visible: !analysisPage.loading && analysisPage.error === ""
                clip: true
                contentWidth: width
                contentHeight: body.implicitHeight
                interactive: body.implicitHeight > height

                ColumnLayout {
                    id: body
                    width: scroll.width
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: spaceCol.implicitHeight + 14
                        radius: 4
                        color: DS.headerBg

                        ColumnLayout {
                            id: spaceCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: 7
                            spacing: 3

                            Text {
                                text: i18n("Espacio en disco")
                                color: DS.subText
                                font.bold: true
                                font.letterSpacing: 0.5
                                font.pixelSize: 11
                                Layout.fillWidth: true
                            }

                            Repeater {
                                model: [
                                    { key: "images", label: "Imágenes" },
                                    { key: "containers", label: "Contenedores" },
                                    { key: "volumes", label: "Volúmenes" },
                                    { key: "buildCache", label: "Caché de build" }
                                ]

                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        text: modelData.label
                                        color: DS.text
                                        font.pixelSize: 12
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        text: {
                                            var entry = analysisPage.summary[modelData.key];
                                            return entry ? entry.size : "—";
                                        }
                                        color: DS.subText
                                        font.family: "monospace"
                                        font.pixelSize: 11
                                    }

                                    Text {
                                        text: {
                                            var entry = analysisPage.summary[modelData.key];
                                            return entry && entry.reclaimBytes > 0
                                                ? i18n("−%1", entry.reclaimable) : "";
                                        }
                                        color: DS.orange
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        Layout.maximumWidth: 96
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1
                                color: DS.divider
                                visible: analysisPage.reclaimableBytes > 0
                            }

                            Text {
                                visible: analysisPage.reclaimableBytes > 0
                                text: i18n("Se pueden liberar %1",
                                    analysisPage.fmtBytes(analysisPage.reclaimableBytes))
                                color: DS.green
                                font.bold: true
                                font.pixelSize: 12
                                Layout.fillWidth: true
                            }
                        }
                    }

                    Text {
                        text: i18n("HALLAZGOS")
                        color: DS.subText
                        font.bold: true
                        font.letterSpacing: 0.5
                        font.pixelSize: 11
                        Layout.fillWidth: true
                        visible: analysisPage.findings.length > 0
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: !analysisPage.loading && analysisPage.findings.length === 0
                        text: i18n("Nada que objetar: todo en orden.\nSin imágenes sin usar, volúmenes huérfanos ni contenedores parados.")
                        color: DS.subText
                        wrapMode: Text.WordWrap
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    }

                    Repeater {
                        model: analysisPage.findings

                        delegate: Rectangle {
                            id: card

                            required property var modelData
                            readonly property var finding: modelData

                            Layout.fillWidth: true
                            Layout.preferredHeight: cardCol.implicitHeight + 14
                            radius: 4
                            color: DS.headerBg
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.05)

                            Rectangle {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 3
                                height: parent.height - 12
                                radius: 1.5
                                color: DS.severityColor(card.finding.severity)
                            }

                            ColumnLayout {
                                id: cardCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.leftMargin: 16
                                anchors.rightMargin: 7
                                anchors.topMargin: 7
                                anchors.bottomMargin: 7
                                spacing: 3

                                Text {
                                    Layout.fillWidth: true
                                    text: card.finding.title || ""
                                    color: DS.text
                                    font.bold: true
                                    font.pixelSize: 12
                                    wrapMode: Text.Wrap
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: card.finding.detail !== ""
                                    text: card.finding.detail || ""
                                    color: DS.subText
                                    font.pixelSize: 11
                                    wrapMode: Text.Wrap
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: analysisPage.targetsText(card.finding) !== ""
                                    text: analysisPage.targetsText(card.finding)
                                    color: DS.faint
                                    font.pixelSize: 10
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    visible: (card.finding.commands || []).length > 0
                                             || (card.finding.hint || "") !== ""
                                    spacing: 5

                                    Repeater {
                                        model: card.finding.commands || []

                                        delegate: ChipButton {
                                            required property var modelData
                                            text: modelData.label
                                            iconColor: modelData.aggressive
                                                ? DS.orange : DS.accentText
                                            accent: !modelData.aggressive
                                            onClicked: {
                                                var subtitle = i18n("Comando: %1", modelData.command);
                                                if (modelData.aggressive) {
                                                    subtitle += "\n\n" + i18n("Acción agresiva: las imágenes que no use ningún contenedor habrá que volver a descargarlas.");
                                                } else {
                                                    subtitle += "\n\n" + i18n("No afecta a los contenedores en marcha.");
                                                }
                                                analysisPage.requestMaintain(
                                                    modelData.target,
                                                    i18n("¿Ejecutar «%1»?", modelData.command),
                                                    subtitle,
                                                    i18n("Ejecutar"));
                                            }
                                        }
                                    }

                                    ChipButton {
                                        visible: (card.finding.hint || "") !== ""
                                        text: i18n("Copiar comando")
                                        icon: Qt.resolvedUrl("../images/icons/copy.svg")
                                        onClicked: analysisPage.copyText(card.finding.hint)
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        Layout.preferredHeight: 4
                    }
                }
            }
        }
    }
}
