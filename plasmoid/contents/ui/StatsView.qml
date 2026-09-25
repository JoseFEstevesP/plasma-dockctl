import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "DockStyle.js" as DS

Item {
    id: statsPage

    anchors.fill: parent

    property var stats: []
    property var meta: ({})
    property bool loading: false
    property string error: ""
    property string sortKey: "cpu"

    signal back()
    signal refreshRequested()
    signal openDetail(string name)

    readonly property var sortKeys: [
        { key: "cpu", label: "CPU" },
        { key: "mem", label: "RAM" },
        { key: "net", label: "Red" },
        { key: "disk", label: "Disco" },
        { key: "pids", label: "Procesos" }
    ]

    readonly property bool available: meta && meta.available === true
    readonly property var total: (meta && meta.total) ? meta.total : ({})
    readonly property real maxValue: {
        var max = 0;
        for (var i = 0; i < statsPage.stats.length; i++) {
            max = Math.max(max, statsPage.metric(statsPage.stats[i]));
        }
        return max;
    }

    function metric(item) {
        switch (statsPage.sortKey) {
        case "mem":
            return item.memBytes || 0;
        case "net":
            return (item.netInBytes || 0) + (item.netOutBytes || 0);
        case "disk":
            return (item.blockInBytes || 0) + (item.blockOutBytes || 0);
        case "pids":
            return item.pids || 0;
        default:
            return item.cpu || 0;
        }
    }

    function metricText(item) {
        switch (statsPage.sortKey) {
        case "mem":
            return item.memUsage || "";
        case "net":
            return item.netIo || "";
        case "disk":
            return item.blockIo || "";
        case "pids":
            return i18n("%1 procesos", item.pids || 0);
        default:
            return (item.cpu || 0).toFixed(2) + " %";
        }
    }

    function secondaryText(item) {
        return i18n("RAM %1 · %2 procs.", item.memUsage || "—", item.pids || 0);
    }

    function barColor(item) {
        if (statsPage.sortKey === "mem") {
            if ((item.memPercent || 0) >= 80) {
                return DS.danger;
            }
            if ((item.memPercent || 0) >= 60) {
                return DS.orange;
            }
            return DS.accent;
        }
        if (statsPage.sortKey === "cpu") {
            if ((item.cpu || 0) >= 80) {
                return DS.danger;
            }
            if ((item.cpu || 0) >= 50) {
                return DS.orange;
            }
            return DS.accent;
        }
        return DS.subText;
    }

    function fmtBytes(count) {
        if (!count || count <= 0) {
            return "0 B";
        }
        if (count >= 1073741824) {
            return (count / 1073741824).toFixed(1) + " GB";
        }
        if (count >= 1048576) {
            return Math.round(count / 1048576) + " MB";
        }
        if (count >= 1024) {
            return Math.round(count / 1024) + " kB";
        }
        return count + " B";
    }

    function fmtAge(seconds) {
        var s = Math.max(0, Math.round(seconds || 0));
        return s < 60 ? i18n("hace %1 s", s) : i18n("hace %1 min", Math.round(s / 60));
    }

    function sorted() {
        var arr = [];
        for (var i = 0; i < statsPage.stats.length; i++) {
            arr.push(statsPage.stats[i]);
        }
        arr.sort(function(a, b) {
            return statsPage.metric(b) - statsPage.metric(a);
        });
        return arr;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        PageHeader {
            title: i18n("Consumo")
            onBack: statsPage.back()
            onRefreshRequested: statsPage.refreshRequested()
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: DS.divider
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: statsPage.sortKeys

                delegate: ChipButton {
                    text: modelData.label
                    accent: statsPage.sortKey === modelData.key
                    onClicked: statsPage.sortKey = modelData.key
                }
            }

            Item {
                Layout.fillWidth: true
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: summaryCol.implicitHeight + 14
            radius: 4
            color: DS.headerBg

            ColumnLayout {
                id: summaryCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 7
                spacing: 2

                Text {
                    text: i18n("%1 en marcha · CPU %2 · RAM %3",
                        statsPage.total.count || 0,
                        (statsPage.total.cpu || 0).toFixed(1) + " %",
                        statsPage.fmtBytes(statsPage.total.memBytes))
                    color: DS.text
                    font.bold: true
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Text {
                    visible: statsPage.available
                    text: i18n("%1 procesos · %2", statsPage.total.pids || 0,
                        statsPage.fmtAge(statsPage.meta ? statsPage.meta.age : 0))
                    color: DS.faint
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
                anchors.centerIn: parent
                visible: statsPage.loading
                text: i18n("Midiendo consumo…")
                color: DS.subText
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
            }

            Text {
                anchors.centerIn: parent
                visible: !statsPage.loading && statsPage.error !== ""
                text: statsPage.error
                color: DS.danger
                width: parent.width - Kirigami.Units.largeSpacing * 2
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }

            Text {
                anchors.centerIn: parent
                visible: !statsPage.loading && statsPage.error === ""
                        && statsPage.available && statsPage.stats.length === 0
                text: i18n("Sin contenedores en marcha")
                color: DS.subText
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
            }

            Text {
                anchors.centerIn: parent
                visible: !statsPage.loading && statsPage.error === "" && !statsPage.available
                text: i18n("Este sistema no permite medir el consumo.\ndocker stats necesita cgroups v2 y permisos sobre el socket.")
                color: DS.subText
                width: parent.width - Kirigami.Units.largeSpacing * 2
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }

            Flickable {
                id: scroll
                anchors.fill: parent
                visible: !statsPage.loading && statsPage.error === ""
                        && statsPage.available && statsPage.stats.length > 0
                clip: true
                contentWidth: width
                contentHeight: rowsCol.implicitHeight
                interactive: rowsCol.implicitHeight > height

                ColumnLayout {
                    id: rowsCol
                    width: scroll.width
                    spacing: 2

                    Repeater {
                        model: statsPage.sorted()

                        delegate: Item {
                            id: statRow

                            Layout.fillWidth: true
                            implicitHeight: statLayout.implicitHeight + 10

                            readonly property var item: modelData
                            property bool hovered: false

                            Rectangle {
                                anchors.fill: parent
                                radius: 5
                                color: DS.text
                                opacity: statRow.hovered ? 0.06 : 0
                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 120
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: statRow.hovered = true
                                onExited: statRow.hovered = false
                                onClicked: statsPage.openDetail(statRow.item.name)
                            }

                            ColumnLayout {
                                id: statLayout
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 4
                                spacing: 3

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        text: statRow.item.name || ""
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                        font.bold: true
                                        color: DS.text
                                        font.pixelSize: 12
                                    }

                                    Text {
                                        text: statsPage.metricText(statRow.item)
                                        color: DS.subText
                                        font.family: "monospace"
                                        font.pixelSize: 11
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    MiniBar {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        value: statsPage.maxValue > 0
                                            ? statsPage.metric(statRow.item) / statsPage.maxValue
                                            : 0
                                        fillColor: statsPage.barColor(statRow.item)
                                    }

                                    Text {
                                        text: statsPage.secondaryText(statRow.item)
                                        color: DS.faint
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                        Layout.maximumWidth: statLayout.width * 0.52
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
