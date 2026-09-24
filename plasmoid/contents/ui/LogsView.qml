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

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        PageHeader {
            title: logPage.containerName
            backTooltip: i18n("Volver al detalle")
            onBack: logPage.back()
            onRefreshRequested: logPage.refreshRequested()
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

            Controls.ScrollView {
                anchors.fill: parent
                visible: !logPage.loading && logPage.error === "" && logPage.logs !== ""

                Controls.TextArea {
                    text: logPage.logs
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