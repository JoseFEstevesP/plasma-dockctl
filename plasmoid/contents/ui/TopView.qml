import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "DockStyle.js" as DS

Item {
    id: topPage

    anchors.fill: parent

    property string containerName: ""
    property var processData: null
    property bool loading: false
    property string error: ""

    signal back()
    signal refreshRequested()

    readonly property var columns: (processData && processData.columns) ? processData.columns : []
    readonly property var rows: (processData && processData.rows) ? processData.rows : []

    TextEdit {
        id: clipSource
        visible: false
    }

    function asText() {
        clipSource.text = tableLines().join("\n");
        clipSource.selectAll();
        clipSource.copy();
    }

    function tableLines() {
        var lines = [columns.join("\t")];
        for (var i = 0; i < rows.length; i++) {
            lines.push(rows[i].join("\t"));
        }
        return lines;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        PageHeader {
            title: topPage.containerName
            backTooltip: i18n("Volver al detalle")
            onBack: topPage.back()
            onRefreshRequested: topPage.refreshRequested()

            ChipButton {
                text: i18n("Copiar")
                icon: Qt.resolvedUrl("../images/icons/copy.svg")
                enabled: topPage.rows.length > 0
                onClicked: topPage.asText()
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
                visible: topPage.loading
                text: i18n("Leyendo procesos…")
                color: DS.subText
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
            }

            Text {
                anchors.centerIn: parent
                visible: !topPage.loading && topPage.error !== ""
                text: topPage.error
                color: DS.danger
                width: parent.width - Kirigami.Units.largeSpacing * 2
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }

            Text {
                anchors.centerIn: parent
                visible: !topPage.loading && topPage.error === "" && topPage.rows.length === 0
                text: i18n("Sin procesos en marcha")
                color: DS.subText
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
            }

            Rectangle {
                anchors.fill: parent
                visible: !topPage.loading && topPage.error === "" && topPage.rows.length > 0
                radius: Kirigami.Units.smallSpacing
                color: DS.logBg
                border.color: DS.logBorder
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: topPage.columns.join("  ")
                        color: DS.subText
                        font.family: "monospace"
                        font.bold: true
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: DS.divider
                    }

                    Flickable {
                        id: scroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: width
                        contentHeight: rowsCol.implicitHeight
                        interactive: rowsCol.implicitHeight > height

                        ColumnLayout {
                            id: rowsCol
                            width: scroll.width
                            spacing: 1

                            Repeater {
                                model: topPage.rows

                                delegate: Text {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    text: {
                                        var cells = [];
                                        for (var i = 0; i < modelData.length; i++) {
                                            cells.push(modelData[i]);
                                        }
                                        return cells.join("  ");
                                    }
                                    color: "#d0d4da"
                                    font.family: "monospace"
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: topPage.processData && topPage.processData.truncated
                        text: i18n("Se muestran las primeras 200 líneas; usa «Copiar» para el resto.")
                        color: DS.faint
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
