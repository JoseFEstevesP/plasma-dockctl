import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: detailPage

    anchors.fill: parent

    property var container: null
    property var detailData: null
    property bool loading: false
    property string error: ""

    signal back()
    signal refreshRequested()
    signal requestAction(string name, string action)
    signal openLogs(string name)

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
            color: Kirigami.Theme.textColor
            opacity: 0.15
        }

        Item {
            id: contentArea
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
                anchors.centerIn: parent
                visible: detailPage.loading
                text: i18n("Cargando detalles…")
                color: Kirigami.Theme.textColor
                opacity: 0.6
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
            }

            Text {
                anchors.centerIn: parent
                visible: !detailPage.loading && detailPage.error !== ""
                text: detailPage.error
                color: Kirigami.Theme.negativeTextColor
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
                                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
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
                        color: Kirigami.Theme.textColor
                        opacity: 0.5
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
                        color: Kirigami.Theme.textColor
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
                        color: Kirigami.Theme.textColor
                        opacity: 0.5
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    }

                    Item { Layout.preferredHeight: Kirigami.Units.smallSpacing * 2 }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents.Button {
                            text: detailPage.detailData && detailPage.detailData.running
                                    ? i18n("Parar")
                                    : i18n("Iniciar")
                            icon.name: detailPage.detailData && detailPage.detailData.running
                                        ? "media-playback-stop"
                                        : "media-playback-start"
                            onClicked: detailPage.requestAction(detailPage.container.name,
                                detailPage.detailData && detailPage.detailData.running ? "stop" : "start")
                        }

                        PlasmaComponents.Button {
                            text: i18n("Reiniciar")
                            icon.name: "view-refresh"
                            onClicked: detailPage.requestAction(detailPage.container.name, "restart")
                        }

                        PlasmaComponents.Button {
                            text: i18n("Eliminar")
                            icon.name: "edit-delete"
                            onClicked: detailPage.requestAction(detailPage.container.name, "remove")
                        }

                        Item { Layout.fillWidth: true }

                        PlasmaComponents.Button {
                            text: i18n("Ver logs")
                            icon.name: "text-x-generic"
                            onClicked: detailPage.openLogs(detailPage.container.name)
                        }
                    }
                }
            }
        }
    }

    function stateColor(d) {
        if (!d) {
            return Kirigami.Theme.textColor;
        }
        if (d.running) {
            if (d.health && d.health !== "healthy") {
                return Kirigami.Theme.neutralTextColor;
            }
            return Kirigami.Theme.positiveTextColor;
        }
        var base = Kirigami.Theme.textColor;
        return Qt.rgba(base.r, base.g, base.b, 0.45);
    }

    component InfoLine: RowLayout {
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Text {
            text: parent && parent.label
            width: Kirigami.Units.gridUnit * 9
            elide: Text.ElideRight
            color: Kirigami.Theme.textColor
            opacity: 0.6
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        }

        Text {
            text: parent && parent.value
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Kirigami.Theme.textColor
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        }
    }
}